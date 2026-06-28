
_G.ImageEx = {}

function ImageEx.new(MayBeName,...)
    local image = setmetatable({}, ImageEx);

    if type(MayBeName) == 'string' then
        image.obj = lovr.data.newImage(_G.FileManager.findFile(MayBeName), ...)
        image._FileName = name
    else
        image.obj = lovr.data.newImage(MayBeName, ...)
        image._FileName = ""
    end

    image:InitData()
    return image;
end

function ImageEx:InitData()

    self.renderid = Render.ImageId;
end

ImageEx.__index = function(tab, key, ...)
    local value = rawget(tab, key);
    if value then
        return value;
    end

    if ImageEx[key] then
        return ImageEx[key];
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

ImageEx.__newindex = function(tab, key, value)
    -- if key == 'renderWidth' then
    --     rawset(tab, 'w', value);
    -- elseif key == 'renderHeight' then
    --     rawset(tab, 'h', value);
    -- else
        rawset(tab, key, value);
    -- end
end

function ImageEx:GetObject()
    return self.obj
end

function ImageEx:draw()
    Render.RenderObject(self)
end

function ImageEx:Release()
end
