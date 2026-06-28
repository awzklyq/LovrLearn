_G.app = {}
local metatab =  {
    __call = function(self, param1, ...)
    
    if type(param1) == 'function' then
        table.insert(self, param1);
    else
            for i, v in pairs(self) do
                if type(v) == 'function' then
                    self[i](param1, ...);
                end
            end
        end
    end
  }

  --参数统一
 _G.app.update = setmetatable({},  metatab)

 _G.app.beforrender = setmetatable({},  metatab)

_G.app.render = setmetatable({},  metatab)

_G.app.afterrender = setmetatable({},  metatab)

_G.app.mousepressed = setmetatable({}, metatab)

_G.app.mousemoved = setmetatable({}, metatab)

_G.app.load = setmetatable({},  metatab)

_G.app.mousereleased = setmetatable({},  metatab)

_G.app.keypressed = setmetatable({},  metatab)

_G.app.wheelmoved = setmetatable({},  metatab)

_G.app.resizeWindow = setmetatable({},  metatab)

function lovr.mousereleased(x, y, button, isTouch)
  --  _G.UIHelper.mouseUp(x, y, button, isTouch)    
    if UI.UISystem.mousereleased(button, x, y) == false then
        _G.app.mousereleased(x, y, button, isTouch)
    end
end

function lovr.keypressed(key, scancode, isrepeat)
    -- if  _G.UIHelper.keyDown then
    --     _G.UIHelper.keyDown(key, scancode, isrepeat)
    -- end
    
    _G.app.keypressed(key, scancode, isrepeat)

    
end

function lovr.keyreleased(key)
    -- if _G.UIHelper.keyUp then
    --     _G.UIHelper.keyUp(key)
    -- end
end

function lovr.wheelmoved(x, y)
    -- if  _G.UIHelper.wheelMove then
    --     _G.UIHelper.wheelMove(x, y)
    -- end
    app.wheelmoved(x, y)
end

function lovr.textinput(text)
    -- if _G.UIHelper.textInput then
    --     _G.UIHelper.textInput(text)
    -- end
end

local screenwidth = lovr.system.getWindowWidth()
local screenheight = lovr.system.getWindowHeight()
local BackRect = nil
function lovr.update(dt)
    if RenderSet then
        RenderSet.frameToken = RenderSet.frameToken + 1
        RenderSet.FrameInterval = dt
    end
    --_G.UIHelper.update(dt);
    -- _G.LightManager.update(dt);

    local w = lovr.system.getWindowWidth()
    local h = lovr.system.getWindowHeight()

    if w ~= screenwidth or h ~= screenheight then
        screenwidth = w;
        screenheight = h;
        if RenderSet then
            RenderSet.ScreenWidth =  screenwidth
            RenderSet.ScreenHeight = screenheight
        end

        
        local camera3d = _G.getGlobalCamera3D()
        if camera3d then
            camera3d.aspectRatio = w/h
        end
        _G.app.resizeWindow(w, h)

    end

    -- if TimerManager then
    --     TimerManager.Tick(dt)
    -- end

    _G.app.update(dt);
end

function lovr.draw(Pass)
    _G._SysPass = Pass
    -- \
    -- _G.UIHelper.update(dt);
    -- _G.app.update(dt);
    _G.app.beforrender(Pass);

    _G.app.render(Pass);
    _G.app.afterrender(Pass);
end

function lovr.mousepressed(x, y, button, istouch)
    -- if button == 1 then -- Versions prior to 0.10.0 use the MouseConstant 'l'
    --    printx = x
    --    printy = y
    -- end
    --_G.UIHelper.mouseDown(x, y, button, isTouch)
    if UI.UISystem.mouseDown(button, x, y) == false then
        _G.app.mousepressed(x, y, button, istouch);
    end
 end

 function lovr.mousemoved(x, y, dx, dy, istouch)
    -- if button == 1 then -- Versions prior to 0.10.0 use the MouseConstant 'l'
    --    printx = x
    --    printy = y
    -- end

    --_G.UIHelper.mousemoved(x, y, dx, dy);
    local HasY = not not y
    if y then
        if UI.UISystem.mousemoved(x, y) == false then
            _G.app.mousemoved(x, y, dx, dy, istouch);
        end
    end
 end

 function lovr.load()
    _G.app.load();

    -- love.window.setMode(800, 600, {resizable=true, vsync=false, minwidth=400, minheight=300})

 end

 _G.isKeyDown = function(...)
    return lovr.system.isKeyDown(...)
end