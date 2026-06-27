
_G.Point2D = {}

-- ============================================================
-- Point2D 顶点 Rect 绘制开关
-- ------------------------------------------------------------
-- 历史背景：Point2D:draw() 默认会通过 _Rect 把每个顶点画成一个
-- lw x lw 的小方块（用于 polygon2d 的 _IsRenderPoints 模式），
-- 这条路径在 fire_tower / glass_tower 等启用顶点渲染的塔中是
-- Rect 创建/同步的最大热点（profile 命中 25424 / 8 等）。
--
-- 实际游戏运行时通常不需要看顶点，所以这里加一个全局开关，
-- 默认关闭：draw 会直接短路，不再每帧调 GenerateDrawData，
-- 也不再每帧同步 / 绘制 _Rect。需要调试看顶点时再打开。
-- ============================================================
Point2D.RectDrawEnabled = false

function Point2D.SetRectDrawEnabled(enabled)
    Point2D.RectDrawEnabled = enabled and true or false
end

function Point2D.IsRectDrawEnabled()
    return Point2D.RectDrawEnabled
end

Point2D.Meta = {}

Point2D.Meta.__index = Point2D

Point2D.Meta.__eq = function(myvalue, value)
    return myvalue.x == value.x and myvalue.y == value.y
end

Point2D.Meta.__sub = function(myvalue, value)
    if type(value) == "number" then
        return Point2D.new(myvalue.x - value, myvalue.y - value)
    else
        return Point2D.new(myvalue.x - value.x, myvalue.y - value.y)
    end
end

Point2D.Meta.__div = function(myvalue, value)
    if type(value) == "number" then
        return Point2D.new(myvalue.x / value, myvalue.y / value)
    elseif  type(value) == "table" and (value.renderid == Render.Vector2Id or value.renderid == Render.Point2Id) then
        return Point2D.new(myvalue.x / value.x, myvalue.y / value.y)
    else
        _errorAssert(false, "Point2D.Meta.__div~")
    end  
   
end

Point2D.Meta.__add = function(myvalue, value)
    if type(value) == "number" then
        return Point2D.new(myvalue.x + value, myvalue.y + value)
    else
        return Point2D.new(myvalue.x + value.x, myvalue.y + value.y)
    end
end

Point2D.Meta.__mul = function(myvalue, value)
    if type(value) == 'table' then
        if value.renderid == Render.Matrix2DId then
            return value:MulLeftVector2(myvalue)
        elseif value.renderid == Render.Vector2Id or value.renderid == Render.Point2Id then
            return Point2D.new(myvalue.x * value.x, myvalue.y * value.y)
        else
            _errorAssert(false, 'function Point2D.__mul')
        end
    else
        return Point2D.new(myvalue.x * value, myvalue.y * value)
    end
end

Point2D.Meta.__unm  = function(myvalue)
    return Point2D.new(-myvalue.x, -myvalue.y)
end

function Point2D.new(x, y, lw)-- lw :line width
    local p = setmetatable({}, Point2D.Meta);

    p.x = x or 0
    p.y = y or 0

    p.lw = lw or 4;
    p.color = LColor.new(255,255,255,255)

    p.renderid = Render.Point2Id ;

    return p;
end

function Point2D:CheckInLeftOfLine(InLine)
    local _Center = InLine:GetCenter()
    local _v1 = self - _Center
    local _v2 = InLine:GetEndPoint() - InLine:GetStartPoint()
    return Vector.angleClockwise(_v1, _v2) >= math.pi
end

function Point2D:CheckInLeftOfEdge(InEdge)
    local _Center = InEdge:GetCenter()
    local _v1 = self - _Center
    local _v2 = InEdge:GetP2() - InEdge:GetP1()
    return Vector.angleClockwise(_v1, _v2) >= math.pi
end

function Point2D:ToVector()
    return Vector.new(self.x, self.y)
end

function Point2D:Copy()
    return Point2D.new(self.x, self.y)
end

function Point2D:CheckInLeftOfLineOrEdge(InObj)
    if InObj.renderid == Render.EdgeId then
        return self:CheckInLeftOfEdge(InObj)
    else
        return self:CheckInLeftOfLine(InObj)
    end
end

function Point2D:GenerateDrawData()
    -- 缓存 _Rect 复用：仅在首次调用时分配 Rect 对象，
    -- 之后每帧 draw 只同步位置/尺寸/颜色到已有的 _Rect 上，
    -- 避免在 Polygon2D 启用 RenderPoints 时每帧创建 Rect/Circle/Line
    -- （之前 fire_tower 等 polygon line 模式中是 Rect 创建的最大热点）。
    local r = self._Rect
    if r == nil then
        r = Rect.CreatFromCenter(self.x, self.y, self.lw, self.lw, 'fill')
        self._Rect = r
        r:SetColor(self.color)
    else
        -- 同步位置（CreatFromCenter 是 x - lw*0.5 的左上角）
        local halfLw = self.lw * 0.5
        r.x = self.x - halfLw
        r.y = self.y - halfLw
        if r.w ~= self.lw or r.h ~= self.lw then
            r.w = self.lw
            r.h = self.lw
        end
        -- 同步颜色到 _Rect.color（_Rect.color 是独立 LColor 实例，
        -- 这里直接逐字段拷贝避免触发 LColor.__eq 元方法的额外开销）。
        local c = self.color
        if c then
            local rc = r.color
            rc.r = c.r
            rc.g = c.g
            rc.b = c.b
            rc.a = c.a
        end
    end
end
function Point2D:SetColor(r, g, b, a)
    if g == nil then
        self.color:Set(r)
    else
        self.color.r = r or 255
        self.color.g = g or 255
        self.color.b = b or 255
        self.color.a = a or 255
    end
    if self._Rect then
        self._Rect:SetColor(r, g, b, a)
    end
end

function Point2D.Copy(this)
    return Point2D.new(this.x, this.y)
end

function Point2D:draw()
    -- 默认开关关闭：draw 直接短路，避免在 polygon2d 的
    -- _IsRenderPoints 模式下每帧对每个顶点都调用 GenerateDrawData
    -- （那是 Rect 同步/创建的热点）。需要可视化顶点时调用
    -- Point2D.SetRectDrawEnabled(true) 临时打开。
    if not Point2D.RectDrawEnabled then
        return
    end
    -- 修复：_Rect 是 GenerateDrawData() 内部懒创建的字段，部分调用方
    -- （例如 tower_hud.lua 在 withImmediateDraw 闭包中直接调 :draw()）
    -- 不会显式先调 GenerateDrawData，导致这里 self._Rect 为 nil 而崩溃
    -- (point2d.lua:153 attempt to index field '_Rect' (a nil value))。
    -- 这里在 draw 入口统一调一次 GenerateDrawData：首次会创建 _Rect，
    -- 后续帧只同步位置/尺寸/颜色。
    self:GenerateDrawData()
    self._Rect:draw()
end

function Point2D:AsVector()
    return Vector.new(self.x, self.y)
end


_G.Point2DCollect = {}

function Point2DCollect.new(ps, lw)-- lw :line width
    local p = setmetatable({}, {__index = Point2DCollect});

    p.ps = ps or {}
    p.lw = lw or 1;
    p.color = LColor.new(255,255,255,255)

    p.renderid = Render.Point2DCollectId;

    p:GenerateRenderDatas()

    return p;
end

function Point2DCollect:AddPoint(p)
    self.ps[#self.ps + 1] = p
    self:GenerateRenderDatas()
end

function Point2DCollect:GenerateRenderDatas()
    self.Datas = {}
    for i = 1, #self.ps do
        self.Datas[#self.Datas + 1] = self.ps[i].x
        self.Datas[#self.Datas + 1] = self.ps[i].y
    end
end

function Point2DCollect:SetColor(r, g, b, a)
    self.color.r = r or 255
    self.color.g = g or 255
    self.color.b = b or 255
    self.color.a = a or 255
end


function Point2DCollect:draw()
    Render.RenderObject(self);
end


Point2D.Origin = Point2D.new(0, 0)