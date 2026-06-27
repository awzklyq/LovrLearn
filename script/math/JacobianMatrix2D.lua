_G.JacobianMatrix2D = {}
_G.JacobianMatrix2D._Meta = {__index = JacobianMatrix2D}

_G.JacobianMatrix2D._Meta.__mul = function(self, other)
    return self._Data * other 
end

function JacobianMatrix2D.new()
    local _mt = setmetatable({},JacobianMatrix2D._Meta)
    
    _mt.renderid = Render.JacobianMatrix2DId

    _mt._Data = Matrixs.new(2, 2)

    return _mt
end

JacobianMatrix2D.GenerateFromRAndAngle = function(r, angle)
    local _mt = JacobianMatrix2D.new()

    local _Rad = math.rad(angle)

    local v11 = math.cos(_Rad)
    local v12 = -r * math.sin(_Rad)

    local v21 = math.sin(_Rad)
    local v22 = r * math.cos(_Rad)

    _mt:SetValue(1, 1, v11)
    _mt:SetValue(1, 2, v12)

    _mt:SetValue(2, 1, v21)
    _mt:SetValue(2, 2, v22)
    
    return _mt
end

function JacobianMatrix2D:SetDatas(...)
    self._Data:SetDatas(...)
end

function JacobianMatrix2D:SetValue(i, j, v)
    self._Data:SetValue(i, j, v)
end

function JacobianMatrix2D:GetValue(i, j)
    return self._Data:GetValue(i, j)
end
