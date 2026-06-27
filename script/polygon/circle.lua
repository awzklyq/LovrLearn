_G.Circle = {}

-- 确保对象池模块已经初始化（_G.ObjectPool）：本文件底部的注册块会用到它，
-- 但本文件可能被业务代码先 require，再走到 ObjectPool。
-- 用 pcall 防御：万一对象池模块还不在 LUA path（比如裸跑工具脚本），不影响
-- 原有 Circle.new 的功能。
pcall(require, "script.polygon.object_pool")

-- =============================================================================
-- Per-frame circle batching
-- -----------------------------------------------------------------------------
-- Instead of issuing one draw call per Circle, every filled Circle drawn in a
-- frame is pushed into `Circle._pendingCircles`. After the main render pass
-- finishes (BatchDraw.Flush()), the batch is uploaded to a single
-- CollectCirclesMesh and rendered in one draw call.
-- Line-mode circles still go through the original Render.RenderObject path
-- because CollectCirclesMesh only tessellates filled circles.
--
-- Circles are pushed as *snapshots* taken from a pool: a single Circle object
-- may be reused many times in one frame (shared particle templates, etc.) and
-- pushing a live reference would make every entry collapse to the final
-- state of that shared object at flush time.
-- =============================================================================
Circle._pendingCircles = {}
Circle._snapshotPool = {}
Circle._collectMesh = nil

local function _getCollectMesh()
    if not Circle._collectMesh then
        Circle._collectMesh = CollectCirclesMesh.new()
    end
    return Circle._collectMesh
end

local function _acquireCircleSnapshot()
    local pool = Circle._snapshotPool
    local n = #pool
    if n > 0 then
        local s = pool[n]
        pool[n] = nil
        return s
    end
    return { color = {}, Visible = true }
end

Circle._Meta = {__index = Circle}

-- 把一个 Circle 对象重置成"刚 new 出来"的初始状态，供 ObjectPool.acquire 复用
-- 时调用。fields 必须与 Circle.new 出来的初始状态保持一致，否则池子里取到
-- 的对象会带上一次使用残留下来的脏字段，导致行为异常。
local function _resetCircle(circle, r, x, y, segments)
    circle.r = r
    circle.x = x
    circle.y = y
    circle.seg = segments or 100

    if circle.color and circle.color.Set then
        -- 复用现有 LColor 实例避免再 new 一个；LColor.Set 行为等同 ctor。
        circle.color:Set(255, 255, 255, 255)
    else
        circle.color = LColor.new(255, 255, 255, 255)
    end

    circle.mode = 'line'
    circle.Visible = true
    circle.renderid = Render.CircleId

    -- 清除可能残留的"用户在上一轮使用时挂载的成员"，避免污染下次使用：
    -- 真实业务里挂载的字段非常多（box2d / OutCircle / Center 等），无法
    -- 一一枚举。我们这里只做最关键的几个清空（box2d、Center、OutCircle、
    -- Lines 等是常见的扩展字段）。其他业务字段由调用方在使用前自行赋值。
    circle.box2d = nil
    circle.Center = nil
    circle.OutCircle = nil
    circle.Lines = nil
    circle.SkipBatch = nil

    return circle
end

local function _newCircleRaw(r, x, y, segments)
    local circle = setmetatable({}, Circle._Meta)
    circle.color = LColor.new(255, 255, 255, 255)
    _resetCircle(circle, r, x, y, segments)
    return circle
end

-- 注册到 ObjectPool（如果模块已加载），允许 ObjectPool 在加载界面预创建。
-- 注册操作只走一次：检查 _G.ObjectPool 是否存在，存在则注册。
do
    local OP = rawget(_G, "ObjectPool")
    if OP and OP.register then
        OP.register("Circle", _newCircleRaw, _resetCircle)
    end
end

function Circle.new(r, x, y, segments)
    -- 优先走 ObjectPool（开关关闭或没注册成功时退回 _newCircleRaw 路径）。
    local OP = rawget(_G, "ObjectPool")
    local circle
    if OP and OP.acquire then
        circle = OP.acquire("Circle", r, x, y, segments)
    end
    if not circle then
        circle = _newCircleRaw(r, x, y, segments)
    end

    -- Live-object accounting (script/demo/vampire/ui/object_count_probe.lua).
    -- Single nil check when the probe is disabled, so safe in the hot path.
    local _ocp = rawget(_G, "ObjectCountProbe")
    if _ocp then _ocp.track("Circle", circle) end

    -- Creation-source tracking (script/demo/vampire/object_creation_tracker.lua).
    -- 统计本局关卡内 Circle.new 的调用来源，受 Setting.enableObjectCreationTracker
    -- 控制；关闭或不在 playing 状态时 recordCreation 自身会立刻 return。
    local _oct = rawget(_G, "ObjectCreationTracker")
    if _oct then _oct.recordCreation("Circle") end

    return circle
end

-- 把一个 Circle 对象归还给对象池。调用方使用完毕后调用：
--   c = Circle.new(...) ;  ... ; Circle.release(c)
-- 调用以后请不要再继续使用对象引用，否则会出现 "用着用着对象被别人取走"
-- 这种典型的 use-after-free 风险。
function Circle.release(circle)
    if not circle then return end
    local OP = rawget(_G, "ObjectPool")
    if OP and OP.release then OP.release("Circle", circle) end
end

function Circle:setColor(r, g, b, a)
    if g then
        self.color.r = r;
        self.color.g = g;
        self.color.b = b;
        self.color.a = a;
    else
        self.color:Set(r)
    end
end

Circle.SetColor = Circle.setColor

function Circle:CheckPointIn(p)
    return self:CheckPointInXY(p.x, p.y)
end

function Circle:CheckPointInXY(x, y)
    local xx = x - self.x
    local yy = y - self.y

    return xx * xx + yy * yy < self.r * self.r
end

function Circle:GetDirectionPoints(dir, angle, num)
    dir:normalize()
    local ps = {}
    if num == 0 then
        return ps
    end

    local p1 = dir * self.r 

    ps[#ps + 1] = Vector.new( p1.x + self.x, p1.y + self.y)
    if num == 1 then
        return ps
    end

    num = num - 1

    local AddAngle = 0
    local SubAngle = 0
    
    local mat = Matrix2D.new()
    for i = 1, num do
        mat:SetTranslation(self.x, self.y)
        if i % 2 == 0 then
            AddAngle = AddAngle +  angle
            mat:MulRotationLeft(AddAngle)
        else
            SubAngle = SubAngle - angle
            
            mat:MulRotationLeft(SubAngle)
        end
        
        ps[#ps + 1] = p1 * mat
    end

   
    return ps
end

function Circle:SetMouseEventEable(enable)
    AddEventToPolygonevent(self, enable)
end



function Circle:draw()
    if not self.Visible then return end

    -- Honour the global per-primitive master switch
    -- (Setting.renderPrimitives.circle). Any access guarded with rawget
    -- so this file keeps working even if Setting hasn't been loaded
    -- yet (e.g. during engine bootstrap).
    local _S = rawget(_G, "Setting")
    local _P = _S and _S.renderPrimitives
    if _P and _P.circle == false then return end

    -- Polygon draw-call source tracker（仅当 vampire 模块挂上了全局
    -- _G.DrawCallTracker 时生效；该 tracker 内部还会再判 Setting 总开关
    -- 与 GameState=="playing"，并且总开关关闭时直接 return，零开销）。
    local _T = rawget(_G, "DrawCallTracker")
    if _T and _T.record then _T.record("Circle") end

    -- Screen-space cull: pass the circle's LOCAL AABB straight in.
    -- RenderSet.IsBoundsOutOfScreen already resolves the bounds through
    -- the active love.graphics transform stack (push/translate/scale/
    -- rotate), so pre-transforming them here would double-apply the
    -- transform and incorrectly cull on-screen circles (visible in the
    -- boss preview panels where a translate(cellCX,cellCY)+scale() is
    -- active: circles at local (0,0) would get transformed twice and
    -- land far outside the virtual viewport).
    if RenderSet.IsBoundsOutOfScreen(self.x - self.r, self.y - self.r,
                                     self.x + self.r, self.y + self.r) then return end

    -- For the batch path below we still need the world-space center so
    -- the snapshotted circle renders at the right spot after the caller's
    -- push/pop unwinds. This transformPoint is independent from the cull.
    local wx, wy = love.graphics.transformPoint(self.x, self.y)

    if self.mode == 'line' or not (BatchDraw and BatchDraw.IsEnabled()) then
        -- Line-mode circles are not supported by CollectCirclesMesh (fill only);
        -- also bypass the batch path when the master switch is disabled.
        Render.RenderObject(self);
    else
        -- Filled circle: snapshot current state into a pooled table and
        -- collect for batched rendering in BatchDraw.Flush.
        --
        -- CRITICAL: resolve the circle's position through the CURRENT
        -- love.graphics transform stack at snapshot time. Many callers
        -- (e.g. every vampire insect) issue love.graphics.push/translate/
        -- rotate around their world position and then draw body parts in
        -- LOCAL coordinates like (0, 0). If we merely snapshotted the raw
        -- self.x / self.y, the push/pop would unwind before Flush() runs
        -- and all body parts would collapse to the origin (invisible).
        -- transformPoint bakes the active transform into world space so
        -- the mesh draws correctly regardless of when Flush() fires.
        --
        -- IMPORTANT: also bake the transform's scale into the radius.
        -- The mesh is drawn with an identity transform after pop(), so a
        -- circle authored in DESIGN coordinates inside a push/scale block
        -- (e.g. main.lua's gameDraw uses scale = ScaleUniform to fit the
        -- 1280x720 design canvas into the actual window) would render at
        -- the right CENTER but with the original (design-unit) radius,
        -- making the body visibly smaller than its logical collision
        -- radius. Sample two extra points one radius away on +x / +y axes
        -- and take the post-transform distance to recover the effective
        -- horizontal / vertical scale - works for translate / scale /
        -- rotate combinations alike. We average them so a uniform scale
        -- comes through cleanly; non-uniform scale would visually squash
        -- the circle into an ellipse anyway, so picking the average is
        -- a reasonable approximation for the batch path (callers who
        -- need exact non-uniform behaviour should set SkipBatch).
        local r = self.r
        local wxR, wyR = love.graphics.transformPoint(self.x + r, self.y)
        local wxD, wyD = love.graphics.transformPoint(self.x, self.y + r)
        local sxR = math.sqrt((wxR - wx) * (wxR - wx) + (wyR - wy) * (wyR - wy))
        local syR = math.sqrt((wxD - wx) * (wxD - wx) + (wyD - wy) * (wyD - wy))
        local effR = (sxR + syR) * 0.5
        local snap = _acquireCircleSnapshot()
        snap.x = wx
        snap.y = wy
        snap.r = effR
        snap.seg = self.seg
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
        local list = Circle._pendingCircles
        list[#list + 1] = snap
    end

    if self.box2d then
        self.box2d:draw()
    end
end

-- -----------------------------------------------------------------------------
-- Register the flush callback with BatchDraw. This runs from
-- application.lua's love.draw() before CameraManager.endDraw(), so batched
-- circles (which store world-space coordinates) render under the same camera
-- transform as their immediate-mode counterparts.
-- -----------------------------------------------------------------------------
if _G.BatchDraw and BatchDraw.RegisterFlush then
    BatchDraw.RegisterFlush(function()
        local list = Circle._pendingCircles
        local n = #list
        if n == 0 then return end

        local prevR, prevG, prevB, prevA = love.graphics.getColor()
        local prevBlend, prevAlphaMode = love.graphics.getBlendMode()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setBlendMode("alpha", "alphamultiply")

        local mesh = _getCollectMesh()
        mesh:SetCircles(list)
        mesh:draw()

        love.graphics.setColor(prevR, prevG, prevB, prevA)
        love.graphics.setBlendMode(prevBlend, prevAlphaMode)

        -- Recycle snapshots.
        local pool = Circle._snapshotPool
        for i = n, 1, -1 do
            pool[#pool + 1] = list[i]
            list[i] = nil
        end
    end)
end