require("dofile")
local _pass
function lovr.load()
  local format
 = {
    { 
'VertexPosition', 'vec3'
 },
    { 
'VertexColor', 'vec4'
 }
  }

  mesh = lovr.graphics.newMesh(
format
, {
    {   
0,  .4, 0 ; 1, 0, 0, 1
 },
    { 
-.5, -.4, 0 ; 0, 1, 0, 1
 },
    {  
.5, -.4, 0 ; 0, 0, 1, 1
 }
  })

  _pass = lovr.graphics.newPass()
end

function lovr.draw(pass)
--   _pass:draw(mesh, 
-- 0, 1.7, -1
-- )
    -- _pass:reset()

    -- _pass:text('hello world', 0, 1.7, -5)
    _pass:setViewPose(1, mat4():identity())
    _pass:setProjection('orthographic')
    _pass:setDepthTest()

    local width, height = pass:getDimensions()
    local button = { x = width / 2, y = height / 2, w = 180, h = 60 }

    local mx, my = lovr.system.getMousePosition()
    local pressed = lovr.system.isMouseDown(1)
    local hovered = mx > button.x - button.w / 2 and mx < button.x + button.w / 2 and
                  my > button.y - button.h / 2 and my < button.y + button.h / 2

    if hovered and pressed then
        pass:setColor(.25, .25, .27)
    elseif hovered then
        pass:setColor(.20, .20, .22)
    else
        pass:setColor(.15, .15, .17)
    end

    pass:plane(button.x, button.y, 0, button.w, button.h)

    pass:setColor(1, 1, 1)
    pass:text('Click me!', button.x, button.y, 0)

    lovr.graphics.submit(_pass)
end