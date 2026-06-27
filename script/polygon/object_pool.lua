-- =============================================================================
-- script/polygon/object_pool.lua
-- -----------------------------------------------------------------------------
-- 全局对象池：为 script/polygon 下的 Circle / Rect / Line / Ellipse 以及
-- script/render 下的 Canvas、以及预留的 Proxy 等封装对象提供"取-用-还"的
-- 复用通道，避免每帧 new 出大量短生命周期对象引发的 Lua GC 暴力回收
-- （profile.md 中观察到的 ThornFlowerTower / HamsterTower draw 单帧
--   2329ms / 1909ms 偶发尖峰即为典型 GC 卡顿特征）。
--
-- 使用方式：
--   * 模块本身按"对象类型名"分桶，每个桶是一个数组（栈），存放可复用的对象。
--   * 各 polygon 文件的 `.new(...)` 入口先调 `ObjectPool.acquire(name, ...)`：
--       - 若开关 (Setting.useObjectPool) 关闭：跳过池子，回退到常规 new。
--       - 池中有空闲对象：弹出并通过该类型注册的 _resetter 重置成 new 一致的
--         初始状态；返回给调用方使用。
--       - 池中无空闲对象：调用注册的 _factory 创建一个新对象返回（且当池子
--         未满时会在归还时入池；此处不入池，否则会立刻被覆盖）。
--   * 调用方使用完毕后调 `ObjectPool.release(name, obj)` 把对象塞回桶中：
--       - 桶超过 setting 的容量上限时丢弃多余对象，让 GC 回收。
--   * 加载界面（preRender.lua）负责"预创建" + "退出关卡时裁剪"。
--
-- 对外 API：
--   ObjectPool.register(name, factory, resetter)
--   ObjectPool.acquire(name, ...)
--   ObjectPool.release(name, obj)
--   ObjectPool.prewarm(name, count)        -- 预先创建并入池 count 个对象
--   ObjectPool.trim(name, max)             -- 把池子裁到不超过 max 个对象
--   ObjectPool.trimAll(max)                -- 所有桶统一裁剪
--   ObjectPool.clear(name)                 -- 清空指定桶
--   ObjectPool.clearAll()                  -- 清空所有桶
--   ObjectPool.getStats()                  -- 返回 { name -> {size=, hits=, miss=, prewarmed=} }
--   ObjectPool.isEnabled()                 -- 读取 Setting.useObjectPool（缺省 true）
--   ObjectPool.getDefaultSize()            -- 读取 Setting.objectPoolDefaultSize（缺省 16384）
-- =============================================================================

local ObjectPool = {}
_G.ObjectPool = ObjectPool

-- name -> { factory=fn, resetter=fn(obj, ...) }
local _registry = {}

-- name -> array stack of pooled objects
local _buckets = {}

-- name -> diagnostics counters
local _stats = {}

local DEFAULT_SIZE = 16384  -- 与 setting.lua 中 objectPoolDefaultSize 默认值保持一致（已在原 8192 基础上翻倍）

-- ---- Setting 读取（rawget 防御 Setting 尚未加载） ----
local function _isEnabledFromSetting()
    local S = rawget(_G, "Setting")
    if not S then return true end          -- Setting 未加载时默认开启（与 setting.lua 默认值一致）
    if S.useObjectPool == nil then return true end
    return S.useObjectPool and true or false
end

local function _defaultSizeFromSetting()
    local S = rawget(_G, "Setting")
    if not S then return DEFAULT_SIZE end
    local n = tonumber(S.objectPoolDefaultSize)
    if not n or n < 0 then return DEFAULT_SIZE end
    return math.floor(n)
end

function ObjectPool.isEnabled()
    return _isEnabledFromSetting()
end

function ObjectPool.getDefaultSize()
    return _defaultSizeFromSetting()
end

-- 获取（或惰性创建）某个类型对应的桶 / 计数器。
local function _getBucket(name)
    local b = _buckets[name]
    if not b then
        b = {}
        _buckets[name] = b
    end
    return b
end

local function _getStats(name)
    local s = _stats[name]
    if not s then
        s = { hits = 0, miss = 0, prewarmed = 0, releases = 0, drops = 0 }
        _stats[name] = s
    end
    return s
end

-- 注册一个类型的工厂方法 + 状态重置方法。
--   * factory(...)        -> 等价于直接 new(...) 创建对象的回调
--   * resetter(obj, ...)  -> 把池中复用的对象重置成"刚 new 出来"的状态
-- factory 和 resetter 都由各 polygon 文件在被 require 时自行注入。
function ObjectPool.register(name, factory, resetter)
    if type(name) ~= "string" or name == "" then return end
    _registry[name] = { factory = factory, resetter = resetter }
    _getBucket(name)
    _getStats(name)
end

-- 从池中取一个对象。池子关闭 / 桶为空时回退到 factory()。
function ObjectPool.acquire(name, ...)
    local entry = _registry[name]
    if not entry then return nil end

    local enabled = _isEnabledFromSetting()
    local s = _getStats(name)

    if not enabled then
        -- 开关关闭：直接走原始 new 路径。
        return entry.factory(...)
    end

    local bucket = _getBucket(name)
    local n = #bucket
    if n > 0 then
        local obj = bucket[n]
        bucket[n] = nil
        s.hits = s.hits + 1
        if entry.resetter then
            -- resetter 失败时退化到工厂方法，避免使用半重置态对象。
            local ok = pcall(entry.resetter, obj, ...)
            if not ok then
                s.miss = s.miss + 1
                return entry.factory(...)
            end
        end
        return obj
    end

    s.miss = s.miss + 1
    return entry.factory(...)
end

-- 把对象归还到池中。超过容量上限时丢弃，等待 GC。
function ObjectPool.release(name, obj)
    if obj == nil then return end
    local entry = _registry[name]
    if not entry then return end

    if not _isEnabledFromSetting() then return end

    local s = _getStats(name)
    s.releases = s.releases + 1

    local bucket = _getBucket(name)
    local cap = _defaultSizeFromSetting()
    if cap > 0 and #bucket >= cap then
        -- 池子已经满了，丢弃多余的对象（调用方让出引用后由 GC 回收）。
        s.drops = s.drops + 1
        return
    end

    bucket[#bucket + 1] = obj
end

-- 预先创建 count 个对象塞进池子，加载界面用。
-- 不会重复 prewarm（比如多次进入加载界面时），通过当前桶大小判断是否需要补足。
function ObjectPool.prewarm(name, count)
    local entry = _registry[name]
    if not entry then return 0 end

    count = tonumber(count) or _defaultSizeFromSetting()
    if count <= 0 then return 0 end

    local bucket = _getBucket(name)
    local s = _getStats(name)
    local need = count - #bucket
    if need <= 0 then return 0 end

    local created = 0
    for _ = 1, need do
        -- 用 factory(默认参数) 创建一个对象后立刻塞回池中；调用 acquire 时
        -- 会调用对应类型的 resetter 把状态校准到调用方真正想要的参数。
        local ok, obj = pcall(entry.factory)
        if ok and obj ~= nil then
            bucket[#bucket + 1] = obj
            created = created + 1
        else
            break
        end
    end
    s.prewarmed = s.prewarmed + created
    return created
end

-- 单桶裁剪：超过 max 时丢弃多余，让 GC 回收。
function ObjectPool.trim(name, max)
    local bucket = _buckets[name]
    if not bucket then return 0 end
    max = tonumber(max) or _defaultSizeFromSetting()
    if max < 0 then max = 0 end

    local n = #bucket
    if n <= max then return 0 end

    local dropped = 0
    for i = n, max + 1, -1 do
        bucket[i] = nil
        dropped = dropped + 1
    end
    local s = _getStats(name)
    s.drops = s.drops + dropped
    return dropped
end

-- 一次性裁剪所有已注册的桶。
function ObjectPool.trimAll(max)
    max = tonumber(max) or _defaultSizeFromSetting()
    local total = 0
    for name, _ in pairs(_buckets) do
        total = total + ObjectPool.trim(name, max)
    end
    return total
end

function ObjectPool.clear(name)
    if _buckets[name] then _buckets[name] = {} end
end

function ObjectPool.clearAll()
    for k in pairs(_buckets) do _buckets[k] = {} end
end

function ObjectPool.getRegisteredTypes()
    local list = {}
    for k in pairs(_registry) do list[#list + 1] = k end
    table.sort(list)
    return list
end

function ObjectPool.getStats()
    local out = {}
    for name, s in pairs(_stats) do
        local bucket = _buckets[name]
        out[name] = {
            size      = bucket and #bucket or 0,
            hits      = s.hits,
            miss      = s.miss,
            releases  = s.releases,
            drops     = s.drops,
            prewarmed = s.prewarmed,
        }
    end
    return out
end

return ObjectPool
