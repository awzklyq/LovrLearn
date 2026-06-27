-- Font Cache
-- -----------------------------------------------------------------------------
-- Calling love.graphics.setNewFont(size) every frame creates a fresh Font
-- object each call, which is expensive (CPU allocation + GPU atlas build on
-- first render) and a well-known hot spot in LOVE2D. This module caches
-- Font objects by (fontPath, size) so repeated requests are O(1) table
-- lookups.
--
-- Typical usage:
--   local FontCache = require("script.render.font_cache")
--   love.graphics.setFont(FontCache.get(16))        -- default font, size 16
--   love.graphics.setFont(FontCache.get(20, path))  -- custom font
--
-- The cache is process-wide and never evicted; font sizes used in a LOVE2D
-- game are bounded (usually <100 unique sizes) so this is safe.

local FontCache = {}

-- size -> Font object (for the default built-in font)
local defaultCache = {}
-- resolvedPath -> (size -> Font object)
local pathCache = {}
-- size -> Font (for the current i18n language). 该表在调用
-- FontCache.invalidate() 时被清空，以便切换语言后走新字体。
local i18nCache = {}
-- 当 i18n 字体应用于 setFont 后，后续调用不需要重复 setFallbacks。
-- 记录已应用过 fallback 的 Font 对象。
local fallbacksApplied = setmetatable({}, { __mode = "k" })

-- 记录哪些 Font 对象是 LÖVE 默认字体（不能当 fallback 使用，
-- 否则 Font:setFallbacks 会报错）。弱引用避免阻止 GC。
local isDefaultFont = setmetatable({}, { __mode = "k" })

-- 文件名/相对路径 → 真实可读路径 缓存（避免每帧反复 findFile 扫描）。
-- value 为 false 表示该文件确认不存在；string 表示已找到的真实路径。
local resolvedPathCache = {}

-- 把用户传来的字体引用（可能是纯文件名，也可能是相对/绝对路径）
-- 解析成 love.filesystem 可读的路径。优先使用项目里的
-- _G.FileManager.findFile（它会扫描所有 addPath 注册过的目录）。
-- 解析失败返回 nil。
local function resolveFontPath(name)
    if not name or name == "" then return nil end
    local cached = resolvedPathCache[name]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    -- 1) love.filesystem 直接命中（已经是相对资源根的有效路径）
    if love.filesystem.getInfo(name) then
        resolvedPathCache[name] = name
        return name
    end

    -- 2) 通过项目自带的 FileManager 在所有注册目录里搜索
    local fm = _G.FileManager
    if fm and type(fm.findFile) == "function" then
        local p = fm.findFile(name)
        if p and love.filesystem.getInfo(p) then
            resolvedPathCache[name] = p
            return p
        end
    end

    resolvedPathCache[name] = false
    return nil
end

-- Rounding helps collapse near-identical sizes (e.g. 16.001 vs 16.0023
-- that differ only due to layout scale float noise) into a single cached
-- Font. We round to 1 decimal place which is more than enough visually.
local function roundSize(size)
    if not size then return 12 end
    return math.floor(size * 10 + 0.5) / 10
end

-- Returns a cached Font object for the given size (and optional path).
-- On first access for a (path, size) combination the Font is created via
-- love.graphics.newFont and stored; subsequent calls reuse it.
--
-- 当未指定 path 时，自动使用 I18N 当前语言的字体（带回退链），
-- 这样原本走 `FontCache.get(size)` 的调用点不需要任何修改也能在
-- 多语言下正确显示 CJK/西里尔/阿拉伯字符。
--
-- 当传入的 path 是"纯文件名"或"相对路径"时，会通过
-- _G.FileManager.findFile 解析为真实文件；找不到时返回 nil（调用方
-- 应当对 nil 做容错——通常退回到 LÖVE 默认字体）。
function FontCache.get(size, path)
    size = roundSize(size)
    if path then
        local resolved = resolveFontPath(path)
        if not resolved then
            -- 找不到字体文件：返回默认字体而非 nil，保证调用方一定能拿
            -- 到一个可绘制的 Font，避免按钮/文字"完全不显示"的灾难。
            return FontCache.getDefault(size)
        end
        local bucket = pathCache[resolved]
        if not bucket then
            bucket = {}
            pathCache[resolved] = bucket
        end
        local f = bucket[size]
        if not f then
            local ok, font = pcall(love.graphics.newFont, resolved, size)
            if ok and font then
                f = font
            else
                f = FontCache.getDefault(size)
            end
            bucket[size] = f
        end
        return f
    end

    -- 无 path：走 i18n 当前语言字体（getCurrent 内部会处理 fallback）
    return FontCache.getCurrent(size)
end

-- 获取 LÖVE 内置默认字体（不经过 i18n），少数希望强制使用默认字体
-- 的场景（如调试 UI、性能信息）可调用此函数。
function FontCache.getDefault(size)
    size = roundSize(size)
    local f = defaultCache[size]
    if not f then
        f = love.graphics.newFont(size)
        defaultCache[size] = f
        isDefaultFont[f] = true
    end
    return f
end

-- Convenience wrapper: set the active LOVE font to the cached one for
-- `size`. Equivalent to love.graphics.setNewFont(size) but without the
-- per-call allocation. 当未传 path 时，会自动使用
-- I18N 当前语言的字体，并为其设置回退链，从而避免 CJK/
-- 西里尔/阿拉伯等非 Latin 字符出现豆腐方块。
function FontCache.setFont(size, path)
    if path then
        love.graphics.setFont(FontCache.get(size, path))
        return
    end
    love.graphics.setFont(FontCache.getCurrent(size))
end

-- 获取与当前 i18n 语言匹配的字体对象（带回退链）。
-- 由于设置面板可以随时切换语言，invalidate() 会清空该缓存。
function FontCache.getCurrent(size)
    size = roundSize(size)
    local cached = i18nCache[size]
    if cached then return cached end

    -- 懒加载 I18N（避免启动阶段循环依赖）
    local I18N
    do
        local ok, m = pcall(require, "script.demo.vampire.i18n.i18n")
        if ok and type(m) == "table" then I18N = m end
    end

    -- 解析主字体路径（可能是纯文件名 → FileManager 解析）
    local mainName = I18N and I18N.getFontPath and I18N.getFontPath() or nil
    local mainResolved = mainName and resolveFontPath(mainName) or nil

    local f
    if mainResolved then
        f = FontCache.get(size, mainResolved)
    else
        -- 主字体不存在：直接用 LÖVE 默认字体，但仍然尝试为其挂上
        -- fallback 链——这样即使没有主 CJK 字体，至少阿拉伯/CJK
        -- 字符还有机会被某个备用字体渲染出来。
        f = FontCache.getDefault(size)
    end

    -- 设置回退链。Font:setFallbacks(...) 仅接受同一像素 size 创建
    -- 的 Font 对象（LÖVE 11+），不同 size 会触发 "font sizes must
    -- match" 错误。所以这里所有 fallback 都用相同的 size 创建。
    if f and not fallbacksApplied[f] then
        local fbNames = (I18N and I18N.getFontFallbacks) and I18N.getFontFallbacks() or {}
        local fbFonts = {}
        for _, name in ipairs(fbNames) do
            local p = resolveFontPath(name)
            if p and p ~= mainResolved then
                local fb = FontCache.get(size, p)
                -- 不能把默认字体当 fallback，那会导致 setFallbacks 失败
                if fb and fb ~= f and not isDefaultFont[fb] then
                    fbFonts[#fbFonts + 1] = fb
                end
            end
        end
        if #fbFonts > 0 and f.setFallbacks then
            -- 用 pcall 容忍：1) 古老 LÖVE 不支持该 API；2) 偶发的
            -- "font sizes must match" 等错误。即便失败，主字体仍可
            -- 正常绘制（只是 CJK/阿语字符会缺）。
            pcall(f.setFallbacks, f, unpack(fbFonts))
        end
        fallbacksApplied[f] = true
    end

    i18nCache[size] = f
    return f
end

-- 在语言切换时调用：清空与"当前语言"相关的字体缓存，让
-- 下一帧重新按新语言字体建立 Font 对象。主/备字体
-- 本身按路径缓存在 pathCache，用于不同语言共享同一字
-- 体时避免重复加载。
function FontCache.invalidate()
    i18nCache = {}
end

-- Warm up the cache for a batch of sizes. Useful from a preload / loading
-- screen so the very first frame of a view screen doesn't pay the
-- newFont cost.
function FontCache.warmup(sizes, path)
    if type(sizes) ~= "table" then return end
    for i = 1, #sizes do
        FontCache.get(sizes[i], path)
    end
end

-- Debug: current cached entry count.
function FontCache.stats()
    local n = 0
    for _ in pairs(defaultCache) do n = n + 1 end
    for _, bucket in pairs(pathCache) do
        for _ in pairs(bucket) do n = n + 1 end
    end
    return n
end

-- ============================================================================
-- Monkey-patch love.graphics.setNewFont / newFont to automatically use the
-- current i18n language font (with fallback chain).
--
-- 背景：项目里 8 个 UI 文件总共有 50+ 处直接调用
--     love.graphics.setNewFont(size)
-- 这会创建 LÖVE 内置默认字体（仅 Latin/数字），导致中文/韩文/阿语
-- 等非 Latin 字符显示为豆腐方块。逐个文件改成 FontCache.setFont 工程
-- 量大且容易遗漏。这里在模块加载时一次性劫持掉这两个 API：
--   * love.graphics.setNewFont(size)            → 走当前语言字体
--   * love.graphics.setNewFont(path, size)      → 保留原行为（指定字体）
--   * love.graphics.newFont(size)               → 走当前语言字体
--   * love.graphics.newFont(path, size)         → 保留原行为
-- 这样所有原代码不需要改动也能在多语言下正确显示文字。
--
-- 注意：只在 LOVE 环境 + 尚未 patch 时执行一次（用全局标记防重入）。
-- ============================================================================
if love and love.graphics and not _G.__FONT_CACHE_PATCHED__ then
    local origSetNewFont = love.graphics.setNewFont
    local origNewFont    = love.graphics.newFont

    -- 判断第一个参数是否是"字体路径/文件名"（字符串且非纯数字字符）。
    -- LÖVE 的 newFont/setNewFont 签名重载较多，常见三种：
    --   1) (size)                       -- 默认字体 + 指定大小
    --   2) (path, size)                 -- 自定义字体文件
    --   3) (rasterizer)                 -- 极少用
    -- 我们只在情况 1 时改走 i18n 字体，其他情况保留原始行为。
    local function isPathArg(a)
        return type(a) == "string"
    end

    love.graphics.setNewFont = function(a, b, ...)
        if isPathArg(a) then
            -- (path, size, ...) → 用户明确指定了字体，保留原行为
            return origSetNewFont(a, b, ...)
        end
        if type(a) == "number" then
            -- (size) → 走当前语言字体（含 fallback 链）
            local f = FontCache.getCurrent(a)
            if f then
                love.graphics.setFont(f)
                return f
            end
        end
        -- 其它形态（rasterizer/userdata）回退到原 API
        return origSetNewFont(a, b, ...)
    end

    love.graphics.newFont = function(a, b, ...)
        if isPathArg(a) then
            return origNewFont(a, b, ...)
        end
        if type(a) == "number" then
            return FontCache.getCurrent(a)
        end
        return origNewFont(a, b, ...)
    end

    _G.__FONT_CACHE_PATCHED__ = true
end

return FontCache
