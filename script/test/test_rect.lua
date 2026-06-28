
local _Rect1 = Rect.new(10, 10, 100, 100)
_Rect1:SetColor(255, 0, 0, 255)

local _Rect2 = Rect.new(200, 200, 100, 100)
_Rect1:SetColor(255, 255, 0, 255)

local _Circle1 = Circle.new(50, 400, 400)
_Circle1:SetColor(0, 255, 0, 255)
app.render(function(pass)
    _Rect1:draw()
    _Rect2:draw()

    _Circle1:draw()
end)