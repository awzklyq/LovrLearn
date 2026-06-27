_G.Rect = {}

-- 先确保 _G.ObjectPool 已可用，让本文件底部的 register 块能成功注册。
pcall(require, "script.polygon.object_pool")

-- Per-frame rect batching (see CollectRectsMesh in script/polygon/mesh.lua).
-- Rects are pushed as pooled snapshots rather than live references. The same
-- Rect object (e.g. a monster HP bar) can be repositioned and recoloured
-- several times per frame; pushing `self` would collapse every entry to the
-- final state at flush time. Pooling avoids GC churn.
Rect._pendingRects = {}
Rect._snapshotPool = {}
Rect._collectMesh = nil

local function _getRectCollectMesh()
    if not Rect._collectMesh then
        Rect._collectMesh = CollectRectsMesh.new()
    end
    return Rect._collectMesh
end

local function _acquireRectSnapshot()
    local pool = Rect._snapshotPool
    local n = #pool
    if n > 0 then
        local s = pool[n]
        pool[n] = nil
        return s
    end
    return { color = {} }
end

Rect._Meta =  {__index = Rect}

-- 把一个 Rect 重置成"刚 new 出来"的初始状态。注意：原始 Rect.new 会调
-- self:Reset() -> GeneraOutCircle / GeneraLines，这会创建额外的
-- Circle / Line 对象。我们这里同样调用一次 Reset 保持兼容；不过 Circle
-- 内部已经走 ObjectPool（如果开关开启），开销不会重新放大。
local function _resetRect(rect, x, y, w, h, mode)
    rect.x = x or 0
    rect.y = y or 0
    rect.h = h or 1
    rect.w = w or 1

    if rect.color and rect.color.Set then
        rect.color:Set(255, 255, 255, 255)
    else
        rect.color = LColor.new(255, 255, 255, 255)
    end

    rect.mode = mode or 'fill'
    rect.lw = 2

    -- 清空可能挂在上一轮使用中的扩展字段，避免污染。
    rect.box2d = nil
    rect.box2d_state = nil
    rect.img = nil
    rect.SkipBatch = nil
    rect._isHpBar = nil

    rect.renderid = Render.RectId

    rect:Reset()
    return rect
end

local function _newRectRaw(x, y, w, h, mode)
    local rect = setmetatable({}, Rect._Meta)
    rect.color = LColor.new(255, 255, 255, 255)
    _resetRect(rect, x, y, w, h, mode)
    return rect
end

-- 注册到 ObjectPool（开关由 Setting.useObjectPool 控制）。
do
    local OP = rawget(_G, "ObjectPool")
    if OP and OP.register then
        OP.register("Rect", _newRectRaw, _resetRect)
    end
end

function Rect.new(x, y, w, h, mode)
    local OP = rawget(_G, "ObjectPool")
    local rect
    if OP and OP.acquire then
        rect = OP.acquire("Rect", x, y, w, h, mode)
    end
    if not rect then
        rect = _newRectRaw(x, y, w, h, mode)
    end

    -- Live-object accounting (see object_count_probe.lua).
    local _ocp = rawget(_G, "ObjectCountProbe")
    if _ocp then _ocp.track("Rect", rect) end

    -- Creation-source tracking (see object_creation_tracker.lua).
    local _oct = rawget(_G, "ObjectCreationTracker")
    if _oct then _oct.recordCreation("Rect") end

    return rect
end

-- 归还到对象池。调用之后不要再使用旧引用。
function Rect.release(rect)
    if not rect then return end
    local OP = rawget(_G, "ObjectPool")
    if OP and OP.release then OP.release("Rect", rect) end
end

Rect.CreatFromCenter = function(InX, InY, InSizeX, InSizeY, InMode)
    return Rect.new(InX - InSizeX * 0.5, InY - InSizeY * 0.5, InSizeX, InSizeY, InMode)
end

function Rect:Reset()
    self:GeneraOutCircle()

    self:GeneraLines()
end

function Rect:SetColor(r, g, b, a)
    if g ~= nil then
        self.color.r = r;
        self.color.g = g;
        self.color.b = b;
        self.color.a = a;
    else
        self.color:Set(r)
    end
end

Rect.setColor = Rect.SetColor

function Rect:SetMouseEventEable(enable)
    AddEventToPolygonevent(self, enable)
end

function Rect:moveTo(x, y)
    self.x = x; 
    self.y = y;
    if self.box2d then
        self.box2d:setPosition(x, y);
    end
end

function Rect:SetCenterPosition(x, y)
    self.x = x - self.w * 0.5; 
    self.y = y - self.h * 0.5;

    self:Reset()
    if self.box2d then
        self.box2d:setPosition(self.x, self.y);
    end
end

function Rect:GetCenter()
    return Vector.new(self.x + self.w * 0.5,  self.y + self.h * 0.5)
end
function Rect:SetImage(name, ...)
    self.img = ImageEx.new(name, ...)
    self.img.renderWidth = self.w - 1
    self.img.renderHeight = self.h - 1

    self.img.x = self.x + 1
    self.img.y = self.y + 1
end

function Rect:draw()
    -- Honour the global per-primitive master switch
    -- (Setting.renderPrimitives.rect). rawget keeps this safe during
    -- engine bootstrap when Setting may not be loaded yet.
    local _S = rawget(_G, "Setting")
    local _P = _S and _S.renderPrimitives
    if _P and _P.rect == false then return end

    -- Polygon draw-call source tracker（仅当 vampire 模块挂上了全局
    -- _G.DrawCallTracker 时生效；该 tracker 内部还会再判 Setting 总开关
    -- 与 GameState=="playing"，并且总开关关闭时直接 return，零开销）。
    local _T = rawget(_G, "DrawCallTracker")
    if _T and _T.record then _T.record("Rect") end

    -- 怪物血条 Rect 的特殊处理（带 self._isHpBar 标记）：
    --   1) MonsterAnimCache 烘焙阶段（__MonsterAnimBaking == true）
    --      跳过 draw，避免把血条烘焙进每种昆虫的帧 Canvas。
    --   2) Setting.showMonsterHealthBar == false 时全局关闭血条，
    --      让 Setting 里的开关对所有 50+ 种昆虫子类统一生效（子类
    --      draw 里调用的是 self._hpBarBg:draw() / self._hpBarFg:draw()，
    --      最终都会走到这里）。
    if self._isHpBar then
        if rawget(_G, "__MonsterAnimBaking") then return end
        if _S and _S.showMonsterHealthBar == false then return end
    end

    if RenderSet.IsBoundsOutOfScreen(self.x, self.y, self.x + self.w, self.y + self.h) then return end

    -- Fill-mode rects with no image are batch-friendly; everything else keeps
    -- the immediate path because image rendering depends on the rect's own
    -- draw() call and line-mode rects aren't supported by CollectRectsMesh.
    -- Rects flagged `SkipBatch` (e.g. the full-screen BackRect used by
    -- application.lua which is rendered in screen space, outside the camera
    -- transform) also stay on the immediate path.
    if self.mode == 'fill' and not self.img and not self.SkipBatch
        and BatchDraw and BatchDraw.IsEnabled() then
        -- Snapshot rather than push self: a single Rect instance is often
        -- reused for many HUD rects in one frame (HP bars, etc).
        -- Also resolve (x, y) through the current transform stack so rects
        -- drawn inside a push/translate/rotate block land at the correct
        -- world-space position when the batched mesh is flushed.
        -- IMPORTANT: the batched mesh is flushed AFTER love.graphics.pop()
        -- restores the caller's UI scale, so we must also bake the
        -- transform's scale into (w, h). Transforming both corners and
        -- rebuilding w/h in screen space gives the correct final size and
        -- position irrespective of any push/scale/translate active when
        -- draw() was called. Rotation is not handled here (a rotated
        -- axis-aligned rect no longer fits a 2-triangle quad); if a caller
        -- relies on rotation they must use the immediate path by setting
        -- SkipBatch = true on the Rect instance.
        local x1, y1 = love.graphics.transformPoint(self.x, self.y)
        local x2, y2 = love.graphics.transformPoint(self.x + self.w, self.y + self.h)
        local sx = x2 - x1
        local sy = y2 - y1
        -- Preserve top-left origin even if the transform flipped/rotated
        -- the axes (rare for UI but keeps semantics consistent).
        if sx < 0 then x1 = x2; sx = -sx end
        if sy < 0 then y1 = y2; sy = -sy end
        local snap = _acquireRectSnapshot()
        snap.x = x1
        snap.y = y1
        snap.w = sx
        snap.h = sy
        local srcCol = self.color
        local dstCol = snap.color
        if srcCol then
            dstCol._r = srcCol._r or 1
            dstCol._g = srcCol._g or 1
            dstCol._b = srcCol._b or 1
            dstCol._a = srcCol._a or 1
        else
            dstCol._r, dstCol._g, dstCol._b, dstCol._a = 1, 1, 1, 1
        end
        local list = Rect._pendingRects
        list[#list + 1] = snap
    else
        Render.RenderObject(self);
    end

    if self.img then
        self.img:draw()
    end

    if self.box2d then
        self.box2d:draw()
    end
end

-- Register the flush callback with BatchDraw. This runs from
-- application.lua's love.draw() before CameraManager.endDraw(), so that
-- batched rects (which store world-space coordinates) are rendered under the
-- same camera transform as their immediate-mode counterparts.
if _G.BatchDraw and BatchDraw.RegisterFlush then
    BatchDraw.RegisterFlush(function()
        local list = Rect._pendingRects
        local n = #list
        if n == 0 then return end

        -- Ensure straight colour + standard alpha blend so per-vertex
        -- colours reach the screen unmodulated (see ellipse.lua for the
        -- same pattern).
        local prevR, prevG, prevB, prevA = love.graphics.getColor()
        local prevBlend, prevAlphaMode = love.graphics.getBlendMode()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setBlendMode("alpha", "alphamultiply")

        local mesh = _getRectCollectMesh()
        mesh:SetRects(list)
        mesh:draw()

        love.graphics.setColor(prevR, prevG, prevB, prevA)
        love.graphics.setBlendMode(prevBlend, prevAlphaMode)

        local pool = Rect._snapshotPool
        for i = n, 1, -1 do
            pool[#pool + 1] = list[i]
            list[i] = nil
        end
    end)
end

function Rect:update(e)
    if self.box2d and self.box2d_state == 'dynamic' then--self.box2d:isDynamic()
        local x, y =  self.box2d.body:getWorldCenter();
        self.x = x -  self.w * 0.5;
        self.y = y -  self.h * 0.5;
    end
 end

 function Rect:CheckPointInXY(x, y)
    return x >= self.x and x < self.x + self.w and y >= self.y and y < self.y + self.h
 end

function Rect:createBox2D(state, ...)
    if self.box2d then
        self.box2d:release();
    end
    self.box2d_state = state;
    self.box2d = Box2dObject:CreateRect(self.x + self.w * 0.5,  self.y +  self.h * 0.5,  self.w,  self.h,state, ...)
 end

function Rect:GeneraOutCircle()
    -- 懒创建 + 字段复用：Rect 走 ObjectPool 复用时，每次 acquire 都会触发
    -- _resetRect -> Reset -> GeneraOutCircle / GeneraLines。如果这里每次都
    -- Circle.new / Line.new，就等于把 Rect 的池化收益清零（池里取出 1 个壳，
    -- 顺手在堆上 new 出 5 个新子对象）。这是 profile_Creator.md 里
    --   "rect.lua:312 GeneraOutCircle <- Reset <- object_pool.lua:125 acquire"
    -- 这条链每帧高频出现 Circle/Line 创建的根因。改为：第一次创建好之后
    -- 仅更新坐标 / 半径 / Center，不再 new。
    local r = math.sqrt(self.w * self.w + self.h * self.h) * 0.5
    local cx = self.x + self.w * 0.5
    local cy = self.y + self.h * 0.5

    if self.OutCircle then
        -- 复用已有 Circle：仅更新几何字段。Center 也复用同一个 Vector，
        -- 避免每次 acquire 都给 Vector 新建一份。
        self.OutCircle.r = r
        self.OutCircle.x = cx
        self.OutCircle.y = cy
        if self.OutCircle.Center then
            self.OutCircle.Center.x = cx
            self.OutCircle.Center.y = cy
        else
            self.OutCircle.Center = Vector.new(cx, cy)
        end
    else
        local center = Vector.new(cx, cy)
        self.OutCircle = Circle.new(r, cx, cy, 50)
        self.OutCircle.Center = center
    end
end

function Rect:GeneraLines()
    -- 懒创建 + 字段复用：与 GeneraOutCircle 同理，避免在 ObjectPool.acquire
    -- 触发的 Reset() 中每次新建 4 条 Line。Line 自身又会在 _resetLine 内调
    -- GeneraOutCircle 创建 1 个 Circle，相当于每次 Rect.acquire 都凭空多出
    -- 1 (Rect.OutCircle) + 4 (Rect.Lines) + 4 (Line[i].OutCircle) = 9 个对象。
    -- 改为：首次创建 4 条 Line 缓存到 self.Lines，后续只更新两端坐标。
    --
    -- 注意：首次创建走 Line.newRaw 而非 Line.new——这 4 条 Line 由 Rect 长期
    -- 持有，跟随 Rect 一起被池化复用，不参与 ObjectPool("Line") 的 acquire/
    -- release 周转。如果走 Line.new，它们会从 Line 池拿货却永远不归还，让
    -- Line 池被慢慢"抽空"，导致后续真正需要临时 Line 的调用方反复
    -- _newLineRaw，pollute 全局 GC。
    local x, y, w, h = self.x, self.y, self.w, self.h
    if self.Lines and self.Lines[1] then
        local l1, l2, l3, l4 = self.Lines[1], self.Lines[2], self.Lines[3], self.Lines[4]
        -- Line 的 _resetLine 会用 _StartPoint / _EndPoint 维护 Vector，
        -- 同时也写 x1/y1/x2/y2 以兼容直接读字段的代码（draw 里就是直接
        -- 读 self.x1/y1/x2/y2）。这里直接复用现有 Line 实例，把 4 个端
        -- 点重置一遍即可。
        local function setLine(L, ax, ay, bx, by)
            if L._StartPoint then L._StartPoint.x, L._StartPoint.y = ax, ay end
            if L._EndPoint   then L._EndPoint.x,   L._EndPoint.y   = bx, by end
            L.x1, L.y1, L.x2, L.y2 = ax, ay, bx, by
        end
        setLine(l1, x,     y,     x + w, y)
        setLine(l2, x + w, y,     x + w, y + h)
        setLine(l3, x + w, y + h, x,     y + h)
        setLine(l4, x,     y + h, x,     y)
        return
    end

    self.Lines = {
        Line.newRaw(x,     y,     x + w, y),
        Line.newRaw(x + w, y,     x + w, y + h),
        Line.newRaw(x + w, y + h, x,     y + h),
        Line.newRaw(x,     y + h, x,     y),
    }
end