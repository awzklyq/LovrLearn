local _Mime = require("mime")

_G._BaseData = {}

_BaseData.Base64_File = function(InFile)
    local encoded = _Mime.b64(lovefile.read(InFile))
    return encoded
end

_BaseData.Base64_File2 = function(InFile)
    local encoded = _Mime.b64(lovefile.read2(InFile))
    return encoded
end