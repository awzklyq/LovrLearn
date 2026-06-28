_G.PassEx = {}

PassEx.__index = function(tab, key, ...)
    local value = rawget(tab, key);
    if value then
        return value;
    end

    if PassEx[key] then
        return PassEx[key];
    end
    
    if tab["obj"] and tab["obj"][key] then
        if type(tab["obj"][key]) == "function" then
            tab[key] = function(tab, ...)
                return tab["obj"][key](tab["obj"], ...);--todo..
            end
            return  tab[key]
        end
        return tab["obj"][key];
    end

    return nil;
end

PassEx.__newindex = function(tab, key, value)
    -- if key == 'renderWidth' then
    --     rawset(tab, 'w', value);
    -- elseif key == 'renderHeight' then
    --     rawset(tab, 'h', value);
    -- else
        rawset(tab, key, value);
    -- end
end


function PassEx.new()
    local _pass = setmetatable({}, _G.PassEx)

    _pass.obj = lovr.graphics.newPass()

    return _pass
end


function PassEx:GetObject()
    return self.obj
end

function PassEx:GetImage()
    return self.obj
end

function PassEx:CreateRenderTarget(InWidth, InHeight)
    local _Texture = TextureEx.new(InWidth, InHeight, TextureOptions.CreateRenderOptions())
    self:setCanvas(_Texture:GetObject())
    self._RenderTargetTexture = _Texture
end

function PassEx:GetRenderTargetTexture()
    return self._RenderTargetTexture
end

local TempDrawPostion = Vector3.new(0, 0, 0)
local TempDrawScale = Vector3.new(1, 1, 1)
function PassEx:DrawTexture(InPass, InTexture, InX, InY, InWidth, InHeight)
    local _TextureWidth = InTexture:getWidth()
    local _TextureHeight = InTexture:getHeight()

    local _PassWidth = InPass:getWidth()
    local _PassHeight = InPass:getHeight()


    InPass:push('transform')
    InPass:origin()
    InPass:setViewPose(1, mat4():identity())
    InPass:setProjection('orthographic')
    InPass:setDepthTest()

    local _sx = _TextureWidth * 0.5 + InX
    local _sy = _TextureHeight * 0.5 + InX
    TempDrawPostion.x = _sx
    TempDrawPostion.y = _sy

    TempDrawScale.x = InWidth or _TextureWidth
    TempDrawScale.y = InHeight or _TextureHeight

    InPass:draw(InTexture.GetObject and InTexture:GetObject() or InTexture, TempDrawPostion, TempDrawScale)
    InPass:pop('transform')
end

function PassEx:DrawRect(InPass, InX, InY, InWidth, InHeight, InColor, InThickness)
    local _PassWidth = InPass:getWidth()
    local _PassHeight = InPass:getHeight()

    InPass:push('state')
    InPass:push('transform')
    InPass:origin()
    InPass:setViewPose(1, mat4():identity())
    InPass:setProjection('orthographic')
    InPass:setDepthTest()

    InPass:setColor(InColor._r, InColor._g, InColor._b, InColor._a)
    -- InPass:roundrect(x, y, z, width, height, thickness, angle, ax, ay, az, radius, segments)
    InPass:roundrect(InX, InY, 0, InWidth, InHeight, InThickness or 1, 0, 0, 0, 0, 0)

    InPass:pop('transform')
    InPass:pop('state')
end

function PassEx:DrawCircle(InPass, InX, InY, InRadius, InColor, InMode)
    InPass:push('state')
    InPass:push('transform')
    InPass:origin()
    InPass:setViewPose(1, mat4():identity())
    InPass:setProjection('orthographic')
    InPass:setDepthTest()

    InPass:setColor(InColor._r, InColor._g, InColor._b, InColor._a)
    -- InPass:circle(x, y, z, radius, angle, ax, ay, az, style, segments)
    InPass:circle(InX, InY, 0, InRadius or 1, 0, 0, 1, 0, InMode or 'line', InSegments or 64)

    InPass:pop('transform')
    InPass:pop('state')
end

function PassEx:DrawLine(InPass, InX1, InY1, InX2, InY2, InColor, InThickness)
    InPass:push('state')
    InPass:push('transform')
    InPass:origin()
    InPass:setViewPose(1, mat4():identity())
    InPass:setProjection('orthographic')
    InPass:setDepthTest()

    InPass:setColor(InColor._r, InColor._g, InColor._b, InColor._a)
    -- lovr Pass:line(...) accepts a list of points: x1,y1,z1, x2,y2,z2, ...
    InPass:line(InX1, InY1, 0, InX2, InY2, 0)

    InPass:pop('transform')
    InPass:pop('state')
end

app.load(function()
    _G._Pass = PassEx.new()

    _Pass:CreateRenderTarget(RenderSet.ScreenWidth, RenderSet.ScreenHeight)

end)