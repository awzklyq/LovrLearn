_G.Ellipse = {}

-- 先确保 _G.ObjectPool 已可用。
pcall(require, "script.polygon.object_pool")

-- Per-frame ellipse batching (see CollectEllipsesMesh in script/polygon/mesh.lua).
-- Ellipses are pushed as *snapshots* (shallow copies of the fields the
-- collector reads) rather than live references. This is critical because the
-- same Ellipse object can be reused many times per frame (e.g. the shared
-- Util._glowOuter / _glowMid / _glowInner halos in vampire demo) - pushing a
-- live reference would make every entry in the pending list collapse to the
-- state of the LAST draw() call for that shared object, which is why the
-- monster glow halos visually "disappeared" once batching was enabled.
Ellipse._pendingEllipses = {}
Ellipse._snapshotPool = {}
Ellipse._collectMesh = nil

local function _getEllipseCollectMesh()
    if not Ellipse._collectMesh then
        Ellipse._collectMesh = CollectEllipsesMesh.new()
    end
    return Ellipse._collectMesh
end

-- Acquire a snapshot table from the pool (or build one). Each snapshot
-- mimics the shape the CollectEllipsesMesh collector expects (x/y/rx/ry/seg
-- plus a .color sub-table carrying _r/_g/_b/_a), so mesh.lua does not need
-- to know about the pooling at all.
local function _acquireSnapshot()
    local pool = Ellipse._snapshotPool
    local n = #pool
    if n > 0 then
        local s = pool[n]
        pool[n] = nil
        return s
    end
    return { color = {} }
end

Ellipse._Meta =  {__index = Ellipse}

-- 把 Ellipse 重置成 Ellipse.new 之后的初始状态，供 ObjectPool 复用。
local function _resetEllipse(ellipse, rx, ry, x, y, segments)
    ellipse.rx = rx or 1
    ellipse.ry = ry or 1
    ellipse.x = x or 0
    ellipse.y = y or 0
    ellipse.seg = segments or 100

    if ellipse.color and ellipse.color.Set then
        ellipse.color:Set(255, 255, 255, 255)
    else
        ellipse.color = LColor.new(255, 255, 255, 255)
    end

    ellipse.mode = 'line'
    ellipse.Visible = true
    ellipse.renderid = Render.EllipseId

    -- 清空可能在上一轮使用中挂载的扩展字段。
    ellipse.box2d = nil
    ellipse.SkipBatch = nil
    return ellipse
end

local function _newEllipseRaw(rx, ry, x, y, segments)
    local ellipse = setmetatable({}, Ellipse._Meta)
    ellipse.color = LColor.new(255, 255, 255, 255)
    _resetEllipse(ellipse, rx, ry, x, y, segments)
    return ellipse
end

do
    local OP = rawget(_G, "ObjectPool")
    if OP and OP.register then
        OP.register("Ellipse", _newEllipseRaw, _resetEllipse)
    end
end

function Ellipse.new(rx, ry, x, y, segments)
    local OP = rawget(_G, "ObjectPool")
    local ellipse
    if OP and OP.acquire then
        ellipse = OP.acquire("Ellipse", rx, ry, x, y, segments)
    end
    if not ellipse then
        ellipse = _newEllipseRaw(rx, ry, x, y, segments)
    end

    -- Live-object accounting (see object_count_probe.lua).
    local _ocp = rawget(_G, "ObjectCountProbe")
    if _ocp then _ocp.track("Ellipse", ellipse) end

    -- Creation-source tracking (see object_creation_tracker.lua).
    local _oct = rawget(_G, "ObjectCreationTracker")
    if _oct then _oct.recordCreation("Ellipse") end

    return ellipse
end

-- 归还 Ellipse 给对象池。之后不要再使用旧引用。
function Ellipse.release(ellipse)
    if not ellipse then return end
    local OP = rawget(_G, "ObjectPool")
    if OP and OP.release then OP.release("Ellipse", ellipse) end
end

function Ellipse:setColor(r, g, b, a)
    if g then
        self.color.r = r;
        self.color.g = g;
        self.color.b = b;
        self.color.a = a;
    else
        self.color:Set(r)
    end
end

Ellipse.SetColor = Ellipse.setColor

function Ellipse:CheckPointIn(p)
    return self:CheckPointInXY(p.x, p.y)
end

function Ellipse:CheckPointInXY(x, y)
    local xx = x - self.x
    local yy = y - self.y

    return (xx * xx) / (self.rx * self.rx) + (yy * yy) / (self.ry * self.ry) < 1
end

function Ellipse:SetMouseEventEable(enable)
    AddEventToPolygonevent(self, enable)
end

function Ellipse:draw()
    if not self.Visible then return end

    -- Honour the global per-primitive master switch
    -- (Setting.renderPrimitives.ellipse). Uses rawget so this stays
    -- safe if Setting is not loaded yet.
    local _S = rawget(_G, "Setting")
    local _P = _S and _S.renderPrimitives
    if _P and _P.ellipse == false then return end

    -- Polygon draw-call source tracker（仅当 vampire 模块挂上了全局
    -- _G.DrawCallTracker 时生效；该 tracker 内部还会再判 Setting 总开关
    -- 与 GameState=="playing"，并且总开关关闭时直接 return，零开销）。
    local _T = rawget(_G, "DrawCallTracker")
    if _T and _T.record then _T.record("Ellipse") end

    -- Screen-space cull: pass the ellipse's LOCAL AABB straight in.
    -- RenderSet.IsBoundsOutOfScreen already resolves the bounds through
    -- the active love.graphics transform stack (push/translate/scale/
    -- rotate), so pre-transforming them here would double-apply the
    -- transform and incorrectly cull on-screen ellipses (e.g. boss aura
    -- halos drawn inside the preview panel's translate+scale block, where
    -- the local ellipse center near (0,0) would be transformed twice and
    -- land far outside the viewport).
    if RenderSet.IsBoundsOutOfScreen(self.x - self.rx, self.y - self.ry,
                                     self.x + self.rx, self.y + self.ry) then return end

    -- For the batch path below we still need the world-space center so
    -- the snapshotted ellipse renders at the right spot after the caller's
    -- push/pop unwinds. This transformPoint is independent from the cull.
    local wx, wy = love.graphics.transformPoint(self.x, self.y)

    if self.mode == 'line' or not (BatchDraw and BatchDraw.IsEnabled()) then
        -- Only fill-mode ellipses are batchable; line-mode keeps the original
        -- immediate draw path.
        Render.RenderObject(self);
    else
        -- Snapshot the current state into a pooled table. Do NOT push `self`
        -- directly: shared ellipse objects (e.g. Util._glowOuter reused per
        -- monster for pulsing halos) would otherwise collapse to a single
        -- final state at flush time, visually dropping every layer but the
        -- last.
        --
        -- CRITICAL: use the wx/wy already resolved above through the
        -- current love.graphics transform stack. Insect draw() methods use
        -- push/translate/rotate and then issue body-part draws in LOCAL
        -- coordinates (see e.g. dragonfly.lua). Without transformPoint,
        -- the snapshotted local coords would be rendered at flush time
        -- AFTER the transform has already been popped, making bodies
        -- disappear.
        --
        -- IMPORTANT: also bake the active transform's scale into rx / ry.
        -- The mesh is rendered with an identity transform after pop(), so
        -- ellipses authored in DESIGN coordinates inside a push/scale
        -- block (e.g. main.lua's gameDraw uses scale = ScaleUniform) would
        -- otherwise render at the right CENTER but with the design-unit
        -- rx / ry, looking visibly smaller than the logical bounds (e.g.
        -- monster body parts vs collision radius mismatch). We sample
        -- one offset point per axis through transformPoint and recover
        -- the effective horizontal / vertical scale; this also handles
        -- the rotation case (post-transform Euclidean distance is the
        -- scale factor regardless of rotation).
        local rx, ry = self.rx, self.ry
        local wxR, wyR = love.graphics.transformPoint(self.x + rx, self.y)
        local wxD, wyD = love.graphics.transformPoint(self.x, self.y + ry)
        local effRx = math.sqrt((wxR - wx) * (wxR - wx) + (wyR - wy) * (wyR - wy))
        local effRy = math.sqrt((wxD - wx) * (wxD - wx) + (wyD - wy) * (wyD - wy))
        local snap = _acquireSnapshot()
        snap.x = wx
        snap.y = wy
        snap.rx = effRx
        snap.ry = effRy
        snap.seg = self.seg
        snap.Visible = true
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

        local list = Ellipse._pendingEllipses
        list[#list + 1] = snap
    end

    if self.box2d then
        self.box2d:draw()
    end
end

-- Register the flush callback with BatchDraw. Runs while the game camera
-- transform is still active (see application.lua love.draw).
if _G.BatchDraw and BatchDraw.RegisterFlush then
    BatchDraw.RegisterFlush(function()
        local list = Ellipse._pendingEllipses
        local n = #list
        if n == 0 then return end

        -- Ensure the mesh draw uses straight (1,1,1,1) colour with the
        -- normal alpha blend, independent of whatever state the last
        -- immediate draw left behind. Without this, per-vertex colours
        -- would get multiplied by the current global colour (often a
        -- dimming tint such as hp-bar red), making the halos look dull
        -- or vanish entirely.
        local prevR, prevG, prevB, prevA = love.graphics.getColor()
        local prevBlend, prevAlphaMode = love.graphics.getBlendMode()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setBlendMode("alpha", "alphamultiply")

        local mesh = _getEllipseCollectMesh()
        mesh:SetEllipses(list)
        mesh:draw()

        love.graphics.setColor(prevR, prevG, prevB, prevA)
        love.graphics.setBlendMode(prevBlend, prevAlphaMode)

        -- Recycle snapshots.
        local pool = Ellipse._snapshotPool
        for i = n, 1, -1 do
            pool[#pool + 1] = list[i]
            list[i] = nil
        end
    end)
end
