_G.Canvas = {}

-- Ensure BatchDraw + CollectCanvasMesh are defined before the register
-- block at the bottom of this file runs. `script/polygon/mesh.lua`
-- declares both on the global table; requiring it here makes the order
-- independent of which file loads canvas.lua first.
pcall(require, "script.polygon.mesh")

-- 先确保 _G.ObjectPool 已可用。
pcall(require, "script.polygon.object_pool")

-- =============================================================================
-- Canvas mesh-batching optimisation
-- -----------------------------------------------------------------------------
-- `Canvas.UseMeshOptimize` is the GLOBAL master switch: when false, NO
-- Canvas instance uses the CollectCanvasMesh path regardless of its
-- per-instance flag. Default: true (game is allowed to use the optimisation
-- unless the user disables it in the settings screen).
--
-- `canvas.meshOptimize` is the PER-INSTANCE opt-in: only Canvases that
-- explicitly set this to true will try to batch via CollectCanvasMesh.
-- Default: false (safe - UI screens and other "single-shot" canvases keep
-- their original direct draw path so they don't accidentally get batched
-- together with world-space canvases). Call `canvas:SetMeshOptimize(true)`
-- to opt a specific canvas into batching (e.g. insect-monster
-- MonsterAnimCache canvases).
--
-- When both switches are true AND BatchDraw is enabled AND the canvas is
-- being drawn via `canvas:draw(x, y, angle, sx, sy, ox, oy)` (or implicitly
-- through Render.RenderObject), the draw is redirected into a shared
-- CollectCanvasMesh collector that is flushed once per frame via
-- BatchDraw.Flush().
-- =============================================================================
Canvas.UseMeshOptimize = true

-- =============================================================================
-- Shared GPU-canvas pool (HashMap)
-- -----------------------------------------------------------------------------
-- 把 `love.graphics.newCanvas(...)` 创建的真实 GPU Canvas 对象从 Canvas 封装
-- 中提取出来，统一存入 _sharedObjs。多个 Canvas 封装实例可以通过同一个
-- shareKey 命中同一份 GPU Canvas，从而避免重复在 GPU 上分配显存。
--
--   _sharedObjs[key] = love-canvas-object
--   _sharedRefs[key] = 引用计数（仅作诊断/调试用，目前未做主动释放）
--
-- 典型使用场景（开关 Canvas.UseSharedObj=true 时）：
--   * 昆虫怪物动画烘焙：同种昆虫的所有实例共享同一组逐帧 GPU Canvas。
--     key 形如 "monster_anim/ant/frame_3"。
--   * 子弹动画烘焙：同种子弹的所有实例共享同一组逐帧 GPU Canvas。
--     key 形如 "bullet_anim/ice/frame_2" / "bullet_anim/ranged_orb/frame_1"。
--
-- `Canvas.UseSharedObj`：全局总开关，默认 false。开启后 AcquireSharedObj
-- 命中既有 GPU Canvas 时直接返回；未命中时通过 factory 创建一份并存入
-- HashMap。关闭时 AcquireSharedObj 等价于直接调用 factory()，保持原有行为。
-- =============================================================================
Canvas.UseSharedObj = false
Canvas._sharedObjs = {}
Canvas._sharedRefs = {}

-- Try to read the master switch directly from Setting on first load so the
-- HashMap is honoured starting from the very first AcquireSharedObj call,
-- without having to wait for setting.lua's app.update sync (which only fires
-- after love.load finishes). Falls back silently when Setting isn't loaded
-- yet — the update-time sync below will catch up.
do
    local okS, S = pcall(require, "script.demo.vampire.setting")
    if okS and type(S) == "table" and S.useCanvasSharedObj ~= nil then
        Canvas.UseSharedObj = S.useCanvasSharedObj and true or false
    end
end

-- Acquire (or create) a shared GPU Canvas keyed by `key`. When the global
-- switch `Canvas.UseSharedObj` is true and the key already exists, the
-- cached GPU Canvas is returned and `factory` is NOT called. Otherwise
-- `factory()` is invoked to build a fresh GPU Canvas; if the switch is
-- on, the freshly built Canvas is also stored in the HashMap so future
-- callers with the same key share it.
--
-- `factory` should be `function() return love.graphics.newCanvas(w, h) end`
-- or similar. Callers that want shareable behaviour must always pass the
-- SAME (w, h) for a given key — the implementation does NOT validate
-- this; mismatched dimensions would silently reuse the first one.
function Canvas.AcquireSharedObj(key, factory)
    if type(factory) ~= "function" then return nil end
    if not Canvas.UseSharedObj or type(key) ~= "string" or key == "" then
        -- Switch off (or no key): just build a fresh GPU Canvas.
        local ok, obj = pcall(factory)
        if not ok then return nil end
        return obj
    end
    local existing = Canvas._sharedObjs[key]
    if existing then
        Canvas._sharedRefs[key] = (Canvas._sharedRefs[key] or 0) + 1
        return existing
    end
    local ok, obj = pcall(factory)
    if not ok or not obj then return nil end
    Canvas._sharedObjs[key] = obj
    Canvas._sharedRefs[key] = 1
    return obj
end

-- Diagnostics: returns (numUniqueGpuCanvases, totalAcquireHits).
-- Useful when verifying the optimisation is actually deduping.
function Canvas.GetSharedObjStats()
    local n, hits = 0, 0
    for _ in pairs(Canvas._sharedObjs) do n = n + 1 end
    for _, c in pairs(Canvas._sharedRefs) do hits = hits + c end
    return n, hits
end

-- Drop the entire shared-object HashMap. The GPU Canvases themselves
-- are not explicitly :release()-ed because callers (e.g. AnimCache)
-- typically still hold references through their own structures and
-- will release on their own clear() pass; this just frees the table
-- so the next AcquireSharedObj call is a clean slate.
function Canvas.ClearSharedObjs()
    Canvas._sharedObjs = {}
    Canvas._sharedRefs = {}
end

-- Shared collector + pending list. Lazily created on first use to avoid
-- allocating a GPU mesh when the feature is disabled.
Canvas._pendingItems = {}
Canvas._itemPool = {}
Canvas._collectMesh = nil

local function _getCanvasCollectMesh()
    if not Canvas._collectMesh then
        Canvas._collectMesh = CollectCanvasMesh.new()
    end
    return Canvas._collectMesh
end

local function _acquireCanvasItem()
    local pool = Canvas._itemPool
    local n = #pool
    if n > 0 then
        local it = pool[n]
        pool[n] = nil
        return it
    end
    return {}
end

-- =============================================================================
-- Canvas wrapper 对象池支持
-- -----------------------------------------------------------------------------
-- 解析 Canvas.new(...) 的可变参数，返回 (args 数组, args 长度, shareKey)。
-- 与原 Canvas.new 保持一致：把最后一个 string 参数当作 shareKey 摘出来，
-- 其余照旧转发给 love.graphics.newCanvas。
local function _parseCanvasArgs(...)
    local args = { ... }
    local nargs = select("#", ...)
    local shareKey = nil
    if nargs > 0 and type(args[nargs]) == "string" then
        shareKey = args[nargs]
        args[nargs] = nil
        nargs = nargs - 1
    end
    return args, nargs, shareKey
end

-- 给 wrapper 重新分配（或保留）GPU canvas 对象，并把字段重置成 Canvas.new
-- 之后的初始状态。这样池中复用的 wrapper 在不同尺寸/格式之间也能被安全
-- 复用（不一致时会 newCanvas 再分配，旧的 GPU canvas 由 LÖVE finalizer
-- 回收；尺寸完全一致时直接保留 GPU canvas，达到真正的零分配复用）。
--
-- ⚠️ 实现注意：本函数内部读取 canvas 上的字段必须**全部使用 rawget**，
-- 写入用 **rawset**。因为 Canvas.__index 的实现里有这么一段：
--     if tab["obj"] and tab["obj"][key] then ... end
-- 当 canvas.obj 为 nil 时（_newCanvasRaw 调进来，或者 prewarm 出来的
-- wrapper 都属于这种），用普通的 `canvas.obj` 读取会走 __index 元方法，
-- 而 __index 内部又会再读 `tab["obj"]` —— 这里 obj 不存在又触发 __index
-- 自己，从而陷入无穷递归 -> stack overflow（boot.lua:352 报错入口就是
-- 由此触发的）。所以本函数里所有字段访问都直接走 raw 路径绕过元方法。
local function _resetCanvas(canvas, ...)
    local args, nargs, shareKey = _parseCanvasArgs(...)

    -- 决定是否能直接复用现有 GPU canvas：仅当池中复用对象的旧尺寸 / 格式
    -- 与新参数完全一致、且没有 shareKey 时直接保留；否则重新分配。
    local oldObj = rawget(canvas, "obj")
    local oldShareKey = rawget(canvas, "_shareKey")
    local reuseGpu = false
    if oldObj and not shareKey and oldShareKey == nil then
        local w = args[1]
        local h = args[2]
        if type(w) == "number" and type(h) == "number"
            and oldObj.getWidth and oldObj.getHeight then
            local ok1, ow = pcall(oldObj.getWidth, oldObj)
            local ok2, oh = pcall(oldObj.getHeight, oldObj)
            if ok1 and ok2 and ow == w and oh == h and nargs <= 2 then
                reuseGpu = true
            end
        end
    end

    if not reuseGpu then
        if shareKey and Canvas.UseSharedObj then
            rawset(canvas, "obj", Canvas.AcquireSharedObj(shareKey, function()
                return love.graphics.newCanvas(unpack(args, 1, nargs))
            end))
        else
            rawset(canvas, "obj", love.graphics.newCanvas(unpack(args, 1, nargs)))
        end
    end
    rawset(canvas, "_shareKey", shareKey)

    local existedTransform = rawget(canvas, "transform")
    if not existedTransform then
        rawset(canvas, "transform", Matrix.new())
    else
        -- Matrix 类没有 SetIdentity 方法，这里直接重新 new 一个保底
        -- （下次 prewarm 出来的 wrapper 已经带上初始 Matrix 了，所以
        -- 实际只在外部业务给 transform 赋过值的极端情况下走这一支）。
        rawset(canvas, "transform", Matrix.new())
    end

    local existedBg = rawget(canvas, "bgColor")
    if existedBg and existedBg.Set then
        existedBg:Set(0, 0, 0)
    else
        rawset(canvas, "bgColor", LColor.new(0, 0, 0))
    end

    rawset(canvas, "renderid", Render.CanvasId)

    -- canvas:getWidth() / getHeight() 走 Canvas.__index 没问题：此时
    -- obj 字段已经被 rawset 上去，rawget 第一步就能命中，不会再触发
    -- __index 内部那段问题代码。这里仍然用方法调用形式，保持与原始
    -- Canvas.new 行为一致（包含 obj:getWidth() 的方法转发缓存）。
    rawset(canvas, "renderWidth", canvas:getWidth())
    rawset(canvas, "renderHeight", canvas:getHeight())
    rawset(canvas, "x", 0)
    rawset(canvas, "y", 0)

    -- 清空可能残留的 per-instance 配置。
    rawset(canvas, "meshOptimize", nil)
    return canvas
end

local function _newCanvasRaw(...)
    local canvas = setmetatable({}, Canvas)
    canvas.transform = Matrix.new()
    canvas.bgColor   = LColor.new(0, 0, 0)
    _resetCanvas(canvas, ...)
    return canvas
end

-- 注册到 ObjectPool；prewarm 阶段会用默认参数 (空) 调用 _newCanvasRaw 创建
-- 一个 1x1 GPU Canvas（实际尺寸由 LÖVE 默认决定，因为没传 w/h 参数）。
-- 每次 acquire 时 _resetCanvas 会按真实参数判断是否需要重新分配 GPU 资源。
do
    local OP = rawget(_G, "ObjectPool")
    if OP and OP.register then
        OP.register("Canvas", _newCanvasRaw, _resetCanvas)
    end
end

function Canvas.new(...)
    -- 优先从 ObjectPool 取一个 Canvas wrapper（仅复用 wrapper Lua 表，
    -- GPU canvas 仍然按调用方实际尺寸/格式新建，避免不同尺寸的 GPU
    -- 资源被错误复用）。GPU 层面的去重交给 Canvas.UseSharedObj /
    -- AcquireSharedObj 完成。
    local OP = rawget(_G, "ObjectPool")
    local canvas
    if OP and OP.acquire then
        canvas = OP.acquire("Canvas", ...)
    end
    if not canvas then
        canvas = _newCanvasRaw(...)
    end

    -- Live-object accounting. The probe (script/demo/vampire/ui/
    -- object_count_probe.lua) is installed at startup as
    -- _G.ObjectCountProbe; it short-circuits to a no-op when the HUD
    -- master switch (Setting.showDrawCallHUD) is off, so this single
    -- nil check is the only cost in the hot path.
    local _ocp = rawget(_G, "ObjectCountProbe")
    if _ocp then _ocp.track("Canvas", canvas) end

    -- Creation-source tracking (see object_creation_tracker.lua).
    -- 同样以 _G.ObjectCreationTracker 形式被 main.lua 注入；关闭或不在
    -- playing 状态时 recordCreation 会立刻 return，零开销。
    local _oct = rawget(_G, "ObjectCreationTracker")
    if _oct then _oct.recordCreation("Canvas") end

    return canvas;
end

-- 归还 Canvas wrapper 给对象池。注意：GPU canvas (.obj) 不会被强制释放，
-- 而是与 wrapper 一起进入池中，下次 acquire 时如果新参数与原 GPU 资源
-- 尺寸/格式不一致，会通过 _resetCanvas 重新调用 love.graphics.newCanvas
-- 创建合适的 GPU 资源（旧的 GPU canvas 由 Lua GC + LÖVE finalizer 回收）。
function Canvas.release(canvas)
    if not canvas then return end
    local OP = rawget(_G, "ObjectPool")
    if OP and OP.release then OP.release("Canvas", canvas) end
end

Canvas.__index = function(tab, key, ...)
    local value = rawget(tab, key);
    if value then
        return value;
    end

    if Canvas[key] then
        return Canvas[key];
    end
    
    if tab["obj"] and tab["obj"][key] then
        if type(tab["obj"][key]) == "function" then
            tab[key] = function(tab, ...)
                return tab["obj"][key](tab["obj"], ...);--todo..
            end
            return  tab[key]
        end
        return tab["obj"][key];
    end

    return nil;
end

Canvas.__newindex = function(tab, key, value)
    rawset(tab, key, value);
end

function Canvas:getPixel(x, y)
    local data = self:newImageData()
    return data:getPixel(x, y);
end

-- Enable / disable the per-instance mesh-batching flag. Does nothing until
-- the global switch (Canvas.UseMeshOptimize) is also true.
function Canvas:SetMeshOptimize(v)
    rawset(self, "meshOptimize", v and true or false)
end

-- Returns true when this canvas is currently allowed to batch draws through
-- CollectCanvasMesh (both the global and instance flags are on, and the
-- BatchDraw subsystem is enabled and ready).
function Canvas:IsMeshOptimizeActive()
    if not Canvas.UseMeshOptimize then return false end
    if not self.meshOptimize then return false end
    if not _G.BatchDraw or not BatchDraw.IsEnabled or not BatchDraw.IsEnabled() then
        return false
    end
    if not _G.CollectCanvasMesh then return false end
    return true
end

-- `Canvas:draw()` supports two call shapes:
--   canvas:draw()                         -- legacy: uses canvas.x / canvas.y
--                                            / canvas.renderWidth / renderHeight
--                                            (routed through Render.RenderObject).
--   canvas:draw(x, y, angle, sx, sy, ox, oy)
--                                         -- "love.graphics.draw-like" - used by
--                                            MonsterAnimCache to place each
--                                            monster's baked frame at its world
--                                            position with rotation. When the
--                                            mesh-optimisation path is enabled,
--                                            this call is redirected into the
--                                            batch collector.
function Canvas:draw(x, y, angle, sx, sy, ox, oy)
    if self:IsMeshOptimizeActive() then
        -- Resolve (x, y) through the current transform stack so canvases
        -- drawn inside a push / translate block land at the right world
        -- coordinates when the mesh is flushed later. Rotation and scale
        -- from the caller (as explicit args) are applied on top of that.
        local wx = x or self.x or 0
        local wy = y or self.y or 0
        local tx, ty = love.graphics.transformPoint(wx, wy)

        -- Per-vertex colour: inherit the current love colour so callers who
        -- set love.graphics.setColor(...) right before drawing still get
        -- tinted output through the batch.
        local cr, cg, cb, ca = love.graphics.getColor()

        local w = self:getWidth()
        local h = self:getHeight()
        local finalSx, finalSy
        if x == nil and y == nil then
            -- Legacy call: scale the canvas to (renderWidth, renderHeight).
            finalSx = (self.renderWidth or w) / w
            finalSy = (self.renderHeight or h) / h
        else
            finalSx = sx or 1
            finalSy = sy or 1
        end

        local it = _acquireCanvasItem()
        it.tex = self.obj
        it.x = tx
        it.y = ty
        it.angle = angle or 0
        it.sx = finalSx
        it.sy = finalSy
        it.ox = ox or 0
        it.oy = oy or 0
        it.w = w
        it.h = h
        it.r = cr
        it.g = cg
        it.b = cb
        it.a = ca
        local list = Canvas._pendingItems
        list[#list + 1] = it
        return
    end

    -- Immediate path. If the caller passed (x, y, angle, ...) we perform the
    -- draw directly via love.graphics.draw so the args are honoured. For the
    -- legacy no-arg call we keep the original Render.RenderObject route so
    -- anything that depends on Render.CanvasId side-effects keeps working.
    if x ~= nil or y ~= nil or angle ~= nil or sx ~= nil or sy ~= nil
        or ox ~= nil or oy ~= nil then
        love.graphics.draw(self.obj, x or 0, y or 0, angle or 0,
            sx or 1, sy or 1, ox or 0, oy or 0)
    else
        Render.RenderObject(self)
    end
end

_G.pushCanvas = function(canvas)
    if canvas.renderid == Render.CanvasId then
        love.graphics.setCanvas(canvas.obj)
    else
        love.graphics.setCanvas(canvas)
    end

    if canvas.bgColor then
        love.graphics.clear(canvas.bgColor._r, canvas.bgColor._g, canvas.bgColor._b, canvas.bgColor._a)
    end
end

_G.popCanvas = function( )
    love.graphics.setCanvas()
end

-- Register a per-frame flush callback with BatchDraw. Runs alongside the
-- other primitive flush callbacks (rect, circle, line, ...) inside
-- application.lua's love.draw loop, so batched canvases render under the
-- same camera transform as their immediate-mode counterparts. Flushes the
-- current pending list via CollectCanvasMesh, draws it, then recycles the
-- pooled item tables back for next frame.
if _G.BatchDraw and BatchDraw.RegisterFlush then
    BatchDraw.RegisterFlush(function()
        local list = Canvas._pendingItems
        local n = #list
        if n == 0 then return end

        local mesh = _getCanvasCollectMesh()
        mesh:SetCanvases(list)
        mesh:draw()

        -- Recycle item tables for next frame.
        local pool = Canvas._itemPool
        for i = n, 1, -1 do
            pool[#pool + 1] = list[i]
            list[i] = nil
        end
    end)
end