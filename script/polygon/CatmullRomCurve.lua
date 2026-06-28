_G.CatmullRomCurve = {}

CatmullRomCurve._Meta = {__index = CatmullRomCurve}

function CatmullRomCurve.new(Points, seg)
    local cr = setmetatable({}, CatmullRomCurve._Meta)

    check(#Points >= 2, "points must be greater than 2")
    cr.Points = Points
    cr.Seg = seg or 20
    cr.DebugLines = {}
    cr._DrawPointsRects = {}
    cr._ShowPointsRect = true
    cr._mouseEventEnable = false
    cr.Color = LColor.new(255, 255, 255, 255)   
    cr:GenerateDebugLines()
    cr:GenerateDrawPointsRect()
    return cr
end

function CatmullRomCurve:GetPoint(InP0, InP1, InP2, InP3, t)
    return (InP1 * 2 + (InP2 - InP0) * t + ( InP0 * 2 - InP1 * 5 + InP2 * 4 - InP3) * t * t + (-InP0 + InP1 * 3 - InP2 * 3 + InP3) * t * t * t) * 0.5
end

function CatmullRomCurve:GenerateDebugLines()
    self.DebugLines = {}

    local _DrawPoints = {}
    for i = 1, #self.Points - 1 do
        local p0
        if i == 1 then
            p0 = self.Points[i]
        else
            p0 = self.Points[i - 1]
        end

        local p3
        if i == #self.Points - 1 then
            p3 = self.Points[i + 1]
        else
            p3 = self.Points[i + 2]
        end

        local p1 = self.Points[i]
        local p2 = self.Points[i + 1]


        for i = 1, self.Seg do
            local t = i / self.Seg
            local p = self:GetPoint(p0, p1, p2, p3, t)
            _DrawPoints[#_DrawPoints + 1] = p
        end
    end

    for i = 1, #_DrawPoints - 1 do
        local line = Line.new(_DrawPoints[i], _DrawPoints[i + 1])
        line:setColor(self.Color.r, self.Color.g, self.Color.b, self.Color.a)
        self.DebugLines[#self.DebugLines + 1] = line
    end
end

function CatmullRomCurve:GenerateDrawPointsRect()
    self._DrawPointsRects = {}
    for i = 1, #self.Points do
        local p = self.Points[i]
        local r = Rect.CreatFromCenter(p.x, p.y, 8, 8)
        r:SetColor(255, 0, 0, 255)
        self._DrawPointsRects[#self._DrawPointsRects + 1] = r
    end
    self:SetPointsRectMouseEventEable(self._mouseEventEnable)
end
function CatmullRomCurve:AddPoint(InPoint)
    self.Points[#self.Points + 1] = InPoint
    self:GenerateDebugLines()
    self:GenerateDrawPointsRect()
end

function CatmullRomCurve:RemovePoint(InIndex)
    table.remove(self.Points, InIndex)
    self:GenerateDebugLines()
    self:GenerateDrawPointsRect()
end

function CatmullRomCurve:SetShowPointsRect(InShow)
    self._ShowPointsRect = InShow
end

function CatmullRomCurve:SetPointsRectMouseEventEable(enable)
    self._mouseEventEnable = enable
    for i = 1, #self._DrawPointsRects do
        local rect = self._DrawPointsRects[i]
        local index = i
        rect:SetMouseEventEable(enable)

        if enable then
            rect.MouseDownEvent = function(r, x, y, button, istouch)
                if self.OnPointMouseDown then
                    self.OnPointMouseDown(index, r, x, y, button, istouch)
                end
            end

            rect.MouseMoveEvent = function(r, x, y, button, istouch)
                r:SetCenterPosition(x, y)
                self.Points[index].x = x
                self.Points[index].y = y
                self:GenerateDebugLines()
                if self.OnPointMouseMove then
                    self.OnPointMouseMove(index, r, x, y, button, istouch)
                end
            end

            rect.MouseUpEvent = function(r, x, y, button, istouch)
                if self.OnPointMouseUp then
                    self.OnPointMouseUp(index, r, x, y, button, istouch)
                end
            end
        end
    end
end

function CatmullRomCurve:SetColor(InR, InG, InB, InA)
    self.Color.r = InR
    self.Color.g = InG
    self.Color.b = InB
    self.Color.a = InA
    for i = 1, #self.DebugLines do
        self.DebugLines[i]:setColor(InR, InG, InB, InA)
    end
end

function CatmullRomCurve:draw()
    for i = 1, #self.DebugLines do
        local line = self.DebugLines[i]
        line:draw()
    end

    if self._ShowPointsRect then
        for i = 1, #self._DrawPointsRects do
            self._DrawPointsRects[i]:draw()
        end
    end
end