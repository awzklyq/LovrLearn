_G.FileManager = {}

-- Check whether the given path exists (file or directory)
local function pathExists(path)
    return lovr.filesystem.isFile(path) or lovr.filesystem.isDirectory(path)
end

_G.FileManager.paths = {}
_G.FileManager.addPath = function(path)
    if lovr.filesystem.isDirectory(path) then
    table.insert(_G.FileManager.paths, path)
    end
end

_G.FileManager.addAllPath = function(path)
    if lovr.filesystem.isDirectory(path) then
        local files = lovr.filesystem.getDirectoryItems(path)
        for i, v in ipairs(files) do
            local temp
            if pathExists(path..'/'..v) then
                temp = path..'/'..v
            elseif pathExists(path..v) then
                temp = path..v
            end
            if temp then
                if lovr.filesystem.isDirectory(temp) then
                    _G.FileManager.addAllPath(temp)
                    table.insert(_G.FileManager.paths, temp)
                end
            end
        end

    end
end

_G.FileManager.findFile = function(file)
    if pathExists(file) then
        return file;
    end
    
    for i, v in ipairs(_G.FileManager.paths) do
       if pathExists(v..file) then
            return v..file;
       end

       if pathExists(v..'/'..file) then
            return v..'/'..file;
       end
   end

   return file
end