_G.TextEx = {}
_G.TextEx._Meta = {__index = _G.TextEx}

_G.TextEx.new = function(InString)
    local text = setmetatable({}, _G.TextEx._Meta)
    return text
end