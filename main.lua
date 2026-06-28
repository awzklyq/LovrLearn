require("dofile")
app.render(function(pass)

    local _pass = _Pass:GetObject()
    -- _pass:push('transform')
    _pass:setViewPose(1, mat4():identity())
    _pass:setProjection('orthographic')
    _pass:setDepthTest()

    local width, height = pass:getDimensions()
    local button = { x = width / 2, y = height / 2, w = 180, h = 60 }

    local mx, my = lovr.system.getMousePosition()
    local pressed = lovr.system.isMouseDown(1)
    local hovered = mx > button.x - button.w / 2 and mx < button.x + button.w / 2 and
                  my > button.y - button.h / 2 and my < button.y + button.h / 2

     _pass:setColor(.255, .0, .0)

    _pass:plane(button.x, button.y, 0, button.w, button.h)

    _pass:setColor(1, 1, 1)
    _pass:text('Click me!', button.x, button.y, 0)

    local _Skip = lovr.graphics.submit(_pass)
    -- _pass:pop('transform')

    -- lovr.graphics.wait()

    -- pass:setViewPose(1, mat4():identity())
    -- pass:setProjection('orthographic')
    -- pass:setDepthTest()
    -- pass:draw(_Pass:GetRenderTargetTexture():GetObject(), 100, 100, 0 , 400)

    PassEx:DrawTexture(pass, _Pass:GetRenderTargetTexture(), 0, 0)
end)