
_G.TextureEx = {}


TextureEx.__index = function(tab, key, ...)
    local value = rawget(tab, key);
    if value then
        return value;
    end

    if TextureEx[key] then
        return TextureEx[key];
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

TextureEx.__newindex = function(tab, key, value)
    -- if key == 'renderWidth' then
    --     rawset(tab, 'w', value);
    -- elseif key == 'renderHeight' then
    --     rawset(tab, 'h', value);
    -- else
        rawset(tab, key, value);
    -- end
end



function TextureEx.new(MayBeName, ...)
    local tex = setmetatable({}, TextureEx);

    if type(MayBeName) == 'string' then
        tex.obj = lovr.graphics.newTexture(_G.FileManager.findFile(MayBeName), ...)
        tex._FileName = name
    else
        tex.obj = lovr.graphics.newTexture(MayBeName, ...)
        tex._FileName = ""
    end

    tex:InitData()
    return tex;
end

function TextureEx:InitData()
    self.renderid = Render.TextureId;
end

function TextureEx:GetObject()
    return self.obj
end

function TextureEx:draw()
    Render.RenderObject(self)
end

function TextureEx:Release()
end


_G.TextureOptions = {}

function TextureOptions.CreateRenderOptions(InTextureType, InTextureFormat, InLinear, InSamples, InMipmaps, InUsage, InLabel)
    local options = {}
    options.TextureType = InTextureType or "2d"
    options.TextureFormat = InTextureFormat or "rgba8"
    options.Linear = InLinear or false
    options.Samples = InSamples or 1
    options.Mipmaps = InMipmaps or false
    options.Usage = InUsage or {"render"} -- {"sample", "render", "storage", "transfer"}
    options.Label = InLabel or "CreateRenderOptions"

    return options
end 