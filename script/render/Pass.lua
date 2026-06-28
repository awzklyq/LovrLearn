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

app.load(function()
    _G._Pass = PassEx.new()

    _Pass:CreateRenderTarget(RenderSet.ScreenWidth, RenderSet.ScreenHeight)

end)