_G.Line = {}

-- 先确保 _G.ObjectPool 已可用。
pcall(require, "script.polygon.object_pool")

-- Per-frame line batching (see CollectLinesMesh in script/polygon/mesh.lua).
-- The same pending list is shared by Line and Lines objects; the collector
-- inspects each entry's renderid to decide how to push vertices.
-- Entries are pooled snapshots (x1/y1/x2/y2/lw/color for single lines, or
-- values[]/lw/color/renderid for polylines) so that shared Line/Lines
-- instances reused multiple times per frame do not alias each other.
Line._pendingLines = {}
Line._snapshotPool = {}
Line._polylineSnapshotPool = {}
Line._polylineValuePool = {}
Line._collectMesh = nil

local function _getLineCollectMesh()
    if not Line._collectMesh then
        Line._collectMesh = CollectLinesMesh.new()
    end
    return Line._collectMesh
end

local function _acquireLineSnapshot()
    local pool = Line._snapshotPool
    local n = #pool
    if n > 0 then
        local s = pool[n]
        pool[n] = nil
        return s
    end
    return { color = {} }
end

local function _acquirePolylineSnapshot()
    local pool = Line._polylineSnapshotPool
    local n = #pool
    if n > 0 then
        local s = pool[n]
        pool[n] = nil
        return s
    end
    -- renderid is set below each time; values[] is filled from source.
    return { color = {}, values = {}, renderid = Render.LinesId }
end

local function _acquirePolylinePoint()
    local pool = Line._polylineValuePool
    local n = #pool
    if n > 0 then
        local p = pool[n]
        pool[n] = nil
        return p
    end
    return {}
end

local LocalLine = Line
LocalLine.Meta = {}
LocalLine.Meta.__index = function(InTable, InKey)
    if InKey == 'x1' then
        return InTable._StartPoint.x
    elseif InKey == 'y1' then
        return InTable._StartPoint.y
    elseif InKey == 'x2' then
        return InTable._EndPoint.x
    elseif InKey == 'y2' then
        return InTable._EndPoint.y
    end

    if LocalLine[InKey] then
        return LocalLine[InKey];
    end


    return rawget(InTable, InKey)
end

LocalLine.Meta.__newindex = function(InTable, key, value)
    if value then
        if key == 'x1' then
            InTable._StartPoint.x = value
        elseif key == 'y1' then
            InTable._StartPoint.y = value
        elseif key == 'x2' then
            InTable._EndPoint.x = value
        elseif key == 'y2' then
            InTable._EndPoint.y =  value
        end
    end

    rawset(InTable, key, value);
end

LocalLine.Meta.__eq = function(myvalue, value)
    return myvalue:IsEqual(value)
end

-- 把一个 Line 重置成 Line.new 的初始状态。注意：复用时会保留并复用
-- _StartPoint / _EndPoint 这两个 Vector 实例（直接写字段而不是 new
-- Vector），这是池子相对于普通 new 的主要收益来源；OutCircle (Circle)
-- 也会被复用，避免每条 Line 都 new 一个 Circle。
local function _resetLine(line, x1, y1, x2, y2, lw)
    -- 确保 _StartPoint / _EndPoint Vector 存在（首次 prewarm 出来的
    -- 桶内对象走过这一步以后就一直保留这两个 Vector 实例）。
    if not line._StartPoint then line._StartPoint = Vector.new() end
    if not line._EndPoint then line._EndPoint = Vector.new() end

    if type(x1) == "table" and type(y1) == "table" then
        -- 调用方传进了两个外部 Vector：直接用它们替换内部 Vector，与原
        -- Line.new 行为一致（外部修改 Vector 也能改动 Line）。
        line._StartPoint = x1
        line._EndPoint = y1
        line.lw = x2 or 2
    else
        -- 数值传参：写回到现有 Vector，不触发 GC。
        line._StartPoint.x = x1 or 0
        line._StartPoint.y = y1 or 0
        line._EndPoint.x = x2 or 1
        line._EndPoint.y = y2 or 1
        line.lw = lw or 2
    end

    if line.color and line.color.Set then
        line.color:Set(255, 255, 255, 255)
    else
        line.color = LColor.new(255, 255, 255, 255)
    end

    -- 重新生成 OutCircle（用现有 Circle 的话 GeneraOutCircle 内部会 new
    -- 一个新的 Circle —— 该 Circle 自身也走 ObjectPool 了，所以 GC 压力
    -- 极低）。如果之前已有 OutCircle，先把它归还到 Circle 池里，避免泄露。
    if line.OutCircle and Circle and Circle.release then
        Circle.release(line.OutCircle)
        line.OutCircle = nil
    end
    line:GeneraOutCircle()
    line.renderid = Render.LineId
    line.IsDrawOutCircle = false
    line._Visible = false

    -- 清空可能残留的扩展字段。
    line.SkipBatch = nil
    return line
end

local function _newLineRaw(x1, y1, x2, y2, lw)
    local line = setmetatable({}, LocalLine.Meta)
    line._StartPoint = Vector.new()
    line._EndPoint = Vector.new()
    line.color = LColor.new(255, 255, 255, 255)
    _resetLine(line, x1, y1, x2, y2, lw)
    return line
end

-- 注册到 ObjectPool（开关由 Setting.useObjectPool 控制）。
do
    local OP = rawget(_G, "ObjectPool")
    if OP and OP.register then
        OP.register("Line", _newLineRaw, _resetLine)
    end
end


function Line.new(x1, y1, x2, y2, lw)-- lw :line width
    -- 优先从 ObjectPool 取一个已经存在的 Line 实例（含 _StartPoint /
    -- _EndPoint Vector 对象）。这样可以避免每帧 Line.new 时新建 2 个
    -- Vector + 1 个 Circle (OutCircle) + 1 个 LColor 的 GC 压力。
    local OP = rawget(_G, "ObjectPool")
    local line
    if OP and OP.acquire then
        line = OP.acquire("Line", x1, y1, x2, y2, lw)
    end
    if not line then
        line = _newLineRaw(x1, y1, x2, y2, lw)
    end

    -- Live-object accounting (see object_count_probe.lua).
    local _ocp = rawget(_G, "ObjectCountProbe")
    if _ocp then _ocp.track("Line", line) end

    -- Creation-source tracking (see object_creation_tracker.lua).
    local _oct = rawget(_G, "ObjectCreationTracker")
    if _oct then _oct.recordCreation("Line") end

    return line;
end

-- 直接构造一个全新的 Line，**不走对象池**。供 Rect/Ellipse/Polygon2D/
-- Triangle 等容器对象在内部首次创建固定数量边线时使用：这些 Line 由容器
-- 长期持有、跟随容器一起复用，不参与 ObjectPool 的 acquire/release 周转，
-- 走对象池反而会污染 Line 池（永远拿不回去）。
function Line.newRaw(x1, y1, x2, y2, lw)
    local line = _newLineRaw(x1, y1, x2, y2, lw)

    -- Live-object accounting (see object_count_probe.lua).
    local _ocp = rawget(_G, "ObjectCountProbe")
    if _ocp then _ocp.track("Line", line) end

    -- Creation-source tracking (see object_creation_tracker.lua).
    local _oct = rawget(_G, "ObjectCreationTracker")
    if _oct then _oct.recordCreation("Line") end

    return line
end

-- 归还 Line 给对象池。之后不要再使用旧引用。
function Line.release(line)
    if not line then return end
    local OP = rawget(_G, "ObjectPool")
    if OP and OP.release then OP.release("Line", line) end
end

function Line:setColor(r, g, b, a)
    self.color.r = r;
    self.color.g = g;
    self.color.b = b;
    self.color.a = a;
end

Line.SetColor = Line.setColor

function Line:IsEqual(line)
    if self._StartPoint == line.c and self._EndPoint == line._StartPoint then
        return true
    end

    if self._StartPoint == line._StartPoint and self._EndPoint == line._EndPoint then
        return true
    end
    
    return false
end


Line.SetColor = Line.setColor

function Line:GeneraOutCircle()
    -- 懒创建 + 字段复用：与 rect.lua 同理，避免 ObjectPool.acquire("Line")
    -- 每次都新建 OutCircle。GeneraOutCircle 在 _resetLine（acquire 路径）
    -- 中被调用，profile_Creator.md 里 13×4 = 52 个 Circle 的根因就是 Rect
    -- 的 4 条 Line 各自又走到这里再 new 一个 Circle。
    local x =  self._EndPoint.x - self._StartPoint.x
    local y =  self._EndPoint.y - self._StartPoint.y

    local r = math.sqrt(x * x + y * y) * 0.5
    local cx = (self._StartPoint.x + self._EndPoint.x) * 0.5
    local cy = (self._StartPoint.y + self._EndPoint.y) * 0.5

    if self.OutCircle then
        self.OutCircle.r = r
        self.OutCircle.x = cx
        self.OutCircle.y = cy
    else
        self.OutCircle = Circle.new(r, cx, cy, 50)
    end
end

function Line:GetStartPoint()
    return self._StartPoint
end

function Line:GetEndPoint()
    return self._EndPoint
end

function Line:GetCenter()
    return (self._StartPoint + self._EndPoint) * 0.5
end

function Line:SetVisible(InVisible)
    self._Visible = InVisible
end

function Line:IsVisible()
    return self._Visible
end

function Line:GetSizeX()
    return math.abs(self._EndPoint.x - self._StartPoint.x)
end

function Line:GetSizeY()
    return math.abs(self._EndPoint.y - self._StartPoint.y)
end

function Line:draw()
    -- Honour the global per-primitive master switch
    -- (Setting.renderPrimitives.line). rawget keeps this safe during
    -- engine bootstrap when Setting may not be loaded yet.
    local _S = rawget(_G, "Setting")
    local _P = _S and _S.renderPrimitives
    if _P and _P.line == false then return end

    -- local r, g, b, a = love.graphics.getColor( );
    local minX = math.min(self.x1, self.x2)
    local minY = math.min(self.y1, self.y2)
    local maxX = math.max(self.x1, self.x2)
    local maxY = math.max(self.y1, self.y2)
    if RenderSet.IsBoundsOutOfScreen(minX, minY, maxX, maxY) then return end

    if BatchDraw and BatchDraw.IsEnabled() then
        -- Snapshot rather than push self (shared Line templates aliasing).
        -- Also resolve both endpoints through the current transform stack so
        -- lines drawn inside a caller's push/translate/rotate block (every
        -- insect body) land at the correct world-space position when the
        -- batched mesh is flushed.
        local wx1, wy1 = love.graphics.transformPoint(self.x1, self.y1)
        local wx2, wy2 = love.graphics.transformPoint(self.x2, self.y2)
        local snap = _acquireLineSnapshot()
        snap.x1 = wx1
        snap.y1 = wy1
        snap.x2 = wx2
        snap.y2 = wy2
        snap.lw = self.lw
        snap.renderid = Render.LineId
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
        local list = Line._pendingLines
        list[#list + 1] = snap
    else
        Render.RenderObject(self);
    end
    -- love.graphics.setColor(r, g, b, a );
    if self.IsDrawOutCircle then
        self.OutCircle:draw()    
    end
end

--https://deepnight.net/tutorial/bresenham-magic-raycasting-line-of-sight-pathfinding/
function Line:GeneratePoints()
    local ps = {}
    local x0 = self.x1
    local y0 = self.y1

    local x1 = self.x2
    local y1 = self.y2

    local swapXY = math.abs(y1 - y0) > math.abs(x1 - x0)
    if swapXY then
        x0 = self.y1
        y0 = self.x1

        x1 = self.y2
        y1 = self.x2
    end

    if x0 > x1 then
        local temp = x0
        x0 = x1
        x1 = temp

        temp = y0
        y0 = y1
        y1 = temp
    end

    local deltax = x1 - x0
    local deltay = math.floor( math.abs(y1 - y0) )
    local _error = math.floor( deltax * 0.5 )
    local y = y0
    local ystep = y1 > y0 and 1 or -1
    for x = x0 - 1, x1 do
        if swapXY then
            ps[#ps + 1] = Point2D.new(y, x)
        else
            ps[#ps + 1] = Point2D.new(x, y)
        end

        _error = _error - deltay
        if _error < 0 then
            y = y + ystep
            _error = _error + deltax
        end
    end
    local points = Point2DCollect.new(ps)
    return points
end

_G.Lines = {}

function Lines.new( )-- lw :line width
    local lines = setmetatable({}, {__index = Lines});
    
    lines.color = LColor.new(255,255,255,255)

    lines.renderid = Render.LinesId ;
    lines.lw = 2;
    lines.values = {}

    -- Live-object accounting (see object_count_probe.lua).
    local _ocp = rawget(_G, "ObjectCountProbe")
    if _ocp then _ocp.track("Line", lines) end

    -- Creation-source tracking (see object_creation_tracker.lua).
    local _oct = rawget(_G, "ObjectCreationTracker")
    if _oct then _oct.recordCreation("Line") end

    return lines;
end

function Lines:addValue(x, y)
    self.values[#self.values + 1] = {x = x, y = y}
end

function Lines:clearValues()
    self.values = {}
end

function Lines:removeValueFromIndex(i)
    table.remove(self.values, i)
end

function Lines:setColor(r, g, b, a)
    self.color.r = r;
    self.color.g = g;
    self.color.b = b;
    self.color.a = a;
end

function Lines:draw()
    -- Honour the global per-primitive master switch
    -- (Setting.renderPrimitives.line).
    local _S = rawget(_G, "Setting")
    local _P = _S and _S.renderPrimitives
    if _P and _P.line == false then return end

    -- local r, g, b, a = love.graphics.getColor( );
    if self.values and #self.values > 0 then
        local minX, minY = self.values[1].x, self.values[1].y
        local maxX, maxY = minX, minY
        for i = 2, #self.values do
            local v = self.values[i]
            if v.x < minX then minX = v.x end
            if v.y < minY then minY = v.y end
            if v.x > maxX then maxX = v.x end
            if v.y > maxY then maxY = v.y end
        end
        if RenderSet.IsBoundsOutOfScreen(minX, minY, maxX, maxY) then return end
    end

    if BatchDraw and BatchDraw.IsEnabled() and self.values and #self.values > 1 then
        -- Polyline snapshot: deep-copy the current values[] into a pooled
        -- snapshot so later mutations (clearValues / addValue) don't affect
        -- what was queued for this frame.
        local snap = _acquirePolylineSnapshot()
        snap.renderid = Render.LinesId
        snap.lw = self.lw
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

        local dstVals = snap.values
        -- Clear any leftover entries from the previous recycle.
        for i = #dstVals, 1, -1 do
            Line._polylineValuePool[#Line._polylineValuePool + 1] = dstVals[i]
            dstVals[i] = nil
        end
        local srcVals = self.values
        for i = 1, #srcVals do
            local sp = srcVals[i]
            local dp = _acquirePolylinePoint()
            -- Resolve each vertex through the current transform stack so
            -- polylines drawn inside push/translate/rotate blocks land at
            -- the correct world-space position at flush time.
            dp.x, dp.y = love.graphics.transformPoint(sp.x, sp.y)
            dstVals[i] = dp
        end

        local list = Line._pendingLines
        list[#list + 1] = snap
    else
        Render.RenderObject(self);
    end
    -- love.graphics.setColor(r, g, b, a );
end
-- function Rect:update(e)
    
--  end

function cross(a, b, c, d)
    return (b.x - a.x)*(d.y - c.y) - (b.y - a.y)*(d.x - c.x)
end

function Lines:IsIntersectLine(line)
    local d1 = cross(a, b, c)
    local d2 = cross(a, b, d)
    local d3 = cross(c, d, a)
    local d4 = cross(c, d, b)
    if d1*d2 < 0 and d3*d4 < 0 then
        return true
    end
    return false
end


_G.CrossLine = {}
function CrossLine.new(x, y, w, h, lw)-- lw :line width
    local line = setmetatable({}, {__index = CrossLine});
    line.x = x or 0;
    line.y = y or 0;
    line.w = w or 1;
    line.h = h or 1;

    line.lw = lw or 2;

    line.color = LColor.new(200,0,0, 255)

    line.renderid = Render.CrossLineId ;

    -- Live-object accounting (see object_count_probe.lua).
    local _ocp = rawget(_G, "ObjectCountProbe")
    if _ocp then _ocp.track("Line", line) end

    -- Creation-source tracking (see object_creation_tracker.lua).
    local _oct = rawget(_G, "ObjectCreationTracker")
    if _oct then _oct.recordCreation("Line") end

    return line;
end

function CrossLine:setColor(r, g, b, a)
    self.color.r = r;
    self.color.g = g;
    self.color.b = b;
    self.color.a = a;
end

function CrossLine:draw()
    -- Honour the global per-primitive master switch
    -- (Setting.renderPrimitives.line).
    local _S = rawget(_G, "Setting")
    local _P = _S and _S.renderPrimitives
    if _P and _P.line == false then return end

    if RenderSet.IsBoundsOutOfScreen(self.x, self.y, self.x + self.w, self.y + self.h) then return end
    Render.RenderObject(self);
end


_G.NoiseLine = {}
function NoiseLine.new(x1, y1, x2, y2, lw, segment, power, speed)-- random
    local line = setmetatable({}, {__index = NoiseLine});
    line.x1 = x1 or 0;
    line.y1 = y1 or 0;
    line.x2 = x2 or 1;
    line.y2 = y2 or 1;

    line.lw = lw or 2;

    line.color = LColor.new(200,0,0, 255)

    line.renderid = Render.NoiseLineId;

    line.tick = 0;

    line.visible = true

    line.power = power or 20

    line.speed = speed or 10

    line.segment = segment or 100

    line:resetData(x1, y1, x2, y2)

    line.mode = "x"

    -- Live-object accounting (see object_count_probe.lua).
    local _ocp = rawget(_G, "ObjectCountProbe")
    if _ocp then _ocp.track("Line", line) end

    -- Creation-source tracking (see object_creation_tracker.lua).
    local _oct = rawget(_G, "ObjectCreationTracker")
    if _oct then _oct.recordCreation("Line") end

    return line;
end

function NoiseLine:resetData(x1, y1, x2, y2)
    self.datas = {}

    self.renderdatas = {}

    self.datas[1]= x1
    self.datas[2]= y1
    self.renderdatas[1]= x1
    self.renderdatas[2]= y1
    local offset = 1 / self.segment

    for i = 1, self.segment do
        self.datas[#self.datas + 1] = math.lerp(x1, x2, offset * i)
        self.datas[#self.datas + 1] = math.lerp(y1, y2, offset * i)

        self.renderdatas[#self.renderdatas + 1] = math.lerp(x1, x2, offset * i)
        self.renderdatas[#self.renderdatas + 1] = math.lerp(y1, y2, offset * i)
        
    end
end

function NoiseLine:setMode(mode)
    self.mode = mode
    self:resetData(self.x1, self.y1, self.x2, self.y2)
end

function NoiseLine:setColor(r, g, b, a)
    self.color.r = r;
    self.color.g = g;
    self.color.b = b;
    self.color.a = a;
end

function NoiseLine:update(e)
    if self.visible then
        for i = 3,  #self.renderdatas - 2, 2 do
            if self.mode == "x" then
                self.renderdatas[i] = self.datas[i] + math.noise(self.datas[i], self.tick * self.speed) * self.power
            else
                self.renderdatas[i + 1] = (self.datas[i + 1] ) + math.noise(i, self.tick * self.speed) * self.power
            end
            -- self.renderdatas[i + 1] = self.datas[i + 1] + math.noise(self.datas[i], self.tick * 10) * 100
        end
        self.tick = self.tick + e

    end

end

function NoiseLine:draw()
    -- Honour the global per-primitive master switch
    -- (Setting.renderPrimitives.line).
    local _S = rawget(_G, "Setting")
    local _P = _S and _S.renderPrimitives
    if _P and _P.line == false then return end

    if self.visible then
        local minX = math.min(self.x1, self.x2) - self.power
        local minY = math.min(self.y1, self.y2) - self.power
        local maxX = math.max(self.x1, self.x2) + self.power
        local maxY = math.max(self.y1, self.y2) + self.power
        if RenderSet.IsBoundsOutOfScreen(minX, minY, maxX, maxY) then return end

        Render.RenderObject(self);
    end
end

-- Register the flush callback with BatchDraw. Line and Lines objects
-- collected during the frame are uploaded to a single CollectLinesMesh and
-- rendered in one draw call while the game camera transform is still active.
if _G.BatchDraw and BatchDraw.RegisterFlush then
    BatchDraw.RegisterFlush(function()
        local list = Line._pendingLines
        local n = #list
        if n == 0 then return end

        local prevR, prevG, prevB, prevA = love.graphics.getColor()
        local prevBlend, prevAlphaMode = love.graphics.getBlendMode()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setBlendMode("alpha", "alphamultiply")

        local mesh = _getLineCollectMesh()
        mesh:SetLines(list)
        mesh:draw()

        love.graphics.setColor(prevR, prevG, prevB, prevA)
        love.graphics.setBlendMode(prevBlend, prevAlphaMode)

        -- Recycle snapshots back to their pools based on renderid.
        local linePool = Line._snapshotPool
        local polyPool = Line._polylineSnapshotPool
        local valPool = Line._polylineValuePool
        for i = n, 1, -1 do
            local snap = list[i]
            if snap.renderid == Render.LinesId then
                local vals = snap.values
                for j = #vals, 1, -1 do
                    valPool[#valPool + 1] = vals[j]
                    vals[j] = nil
                end
                polyPool[#polyPool + 1] = snap
            else
                linePool[#linePool + 1] = snap
            end
            list[i] = nil
        end
    end)
end
