_G.lovrfile = {}

lovrfile.DefaultForder =  'C:/Users/Liuyongqi/AppData/Roaming/lovr/lovr2dgame/'

lovrfile.read = function(filename)
    local file = lovr.filesystem.newFile(_G.FileManager.findFile(filename))
    file:open("r")
    local data = file:read()
    file:close()
    return data
end

-- Lua原生方法读取文件（二进制模式）
lovrfile.read2 = function(filename)
    local file, err = io.open(_G.FileManager.findFile(filename), "rb")
    if not file then
        return nil, err
    end
    local data = file:read("*all")
    file:close()
    return data
end

--获取路径
lovrfile.stripfilename = function(filename)
	return string.match(filename, "(.+)/[^/]*%.%w+$") --*nix system
	--return string.match(filename, “(.+)\\[^\\]*%.%w+$”) — windows
end

--获取文件名
lovrfile.strippath = function(filename)
	return string.match(filename, ".+/([^/]*%.%w+)$") -- *nix system
	--return string.match(filename, “.+\\([^\\]*%.%w+)$”) — *nix system
end

--去除扩展名
lovrfile.stripextension = function(filename)
	local idx = filename:match(".+()%.%w+$")
	if(idx) then
		return filename:sub(1, idx-1)
	else
		return filename
	end
end

--获取扩展名
lovrfile.getextension = function(filename)
	return filename:match(".+%.(%w+)$")
end

lovrfile.exists = function(filename)
	return lovr.filesystem.isFile(filename) or lovr.filesystem.isDirectory(filename)
end

lovrfile.getWorkingDirectory = function()
	return lovr.filesystem.getWorkingDirectory()
end

lovrfile.newFile = function(filename, mode)
	local file, errorstr = lovr.filesystem.newFile(filename, mode )
	return file, errorstr
end

lovrfile.write = function(name, data)
	local f, errorstr = lovrfile.newFile(name)
	f:open("w")
	f:write(data)
	-- f:flush()
	f:close()
end

lovrfile.getUserDirectory = function()
	return lovr.filesystem.getUserDirectory()
end

function Split(szFullString, szSeparator)
	local nFindStartIndex = 1
	local nSplitIndex = 1
	local nSplitArray = {}
	while true do
	   local nFindLastIndex = string.find(szFullString, szSeparator, nFindStartIndex)
	   if not nFindLastIndex then
		nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, string.len(szFullString))
		break
	   end
	   nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, nFindLastIndex - 1)
	   nFindStartIndex = nFindLastIndex + string.len(szSeparator)
	   nSplitIndex = nSplitIndex + 1
	end
	return nSplitArray
end

lovrfile.loadCSV = function(filename)
	-- Read whole file via lovr.filesystem.read, then split into lines.
	local content = lovr.filesystem.read(_G.FileManager.findFile(filename))
	if not content then
		return {}
	end

	local lines = {}
	for line in string.gmatch(content, "([^\r\n]+)") do
		lines[#lines + 1] = line
	end

	if #lines == 0 then
		return {}
	end

	local indexs = Split(lines[1], ",")
	local num = #indexs

	local datas = {}

	for i = 2, #lines do
		local sdata = Split(lines[i], ",")
		local temp = {}
		for j = 1, num do
			local d = sdata[j]
			if tonumber(d) then
				d = tonumber(d)
			elseif d == "" then
				d = nil
			end

			temp[indexs[j]] = d
		end

		datas[#datas + 1] = temp
	end

	return datas
end
