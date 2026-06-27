math.lerp = function(v1, v2, t)
    t  = math.clamp(t, 0, 1);
    return (1-t)*v1 + t *v2;
end

math.clamp = function(v, v1, v2)
    local min = math.min(v1, v2);
    local max = math.max(v1, v2);

    if v < min then
        return min;
    end

    if v > max then
        return max;
    end

    return v;
end

math.clamp_min_max = function(InV, InMin, InMax)
    return  math.min(math.max(InV, InMin), InMax)
end


math.noise = function(...)
    local value = lovr.math.noise( ... )
    return value--2 * value - 1
end

math.NoiseVector3 = function(InV)
    return math.noise(InV.x, InV.y, InV.z )
end

math.NoiseVector2 = function(InV)
    return math.noise(InV.x, InV.y )
end


local GetCross = function(p1, p2, p)
	return (p2.x - p1.x) * (p.y - p1.y) - (p.x - p1.x) * (p2.y - p1.y);
end

math.IsPointInRect = function(p, a, b, c, d)
	return GetCross(a, b, p) * GetCross(c, d, p) >= 0 and GetCross(b, c, p) * GetCross(d, a, p) >= 0;
end


math.LeftMove = function(x, offset)
    assert(offset)

    if luabit then
        return luabit.lshift(x, offset)
    end

    if offset < 1 then
        return x
    end

    local v, _ = math.modf(x)

    return v * math.pow(2, offset)
end

math.RightMove = function(x, offset)
    assert(offset)

    if luabit then
        return luabit.rshift(x, offset)
    end

    if offset < 1 then
        return x
    end

    local v, _ = math.modf(x)
    
    local r, _ =  math.modf(v / math.pow(2, offset))
    return r
end

math.round = function(v)
    return math.floor(v + 0.5)
end



math.BitXor = function(v1, v2)
    if luabit then
        return luabit.bxor(v1, v2)
    end

    local Step = 0
    local result = 0

    v1 = math.modf(v1)
    v2 = math.modf(v2)
    while (v1 ~= 0 or  v2 ~= 0) do
        local r1 = v1 % 2
        local r2 = v2 % 2
        if r1 ~= r2 then
            result = result + math.pow(2, Step)
        else
            result = result + 0
        end

        Step = Step + 1
        v1 = math.RightMove(v1, 1)
        v2 = math.RightMove(v2, 1)
    end
    return result
end

math.BitAnd = function(v1, v2)
    if luabit then
        return luabit.band(v1, v2)
    end

    local Step = 0
    local result = 0

    v1 = math.modf(v1)
    v2 = math.modf(v2)
    while (v1 ~= 0 or  v2 ~= 0) do
        local r1 = v1 % 2
        local r2 = v2 % 2
        if r1 == 1 and r2 == 1 then
            result = result + math.pow(2, Step)
        else
            result = result + 0
        end

        Step = Step + 1
        v1 = math.RightMove(v1, 1)
        v2 = math.RightMove(v2, 1)
    end
    return result
end

math.BitOr = function(v1, v2)
    if luabit then
        return luabit.bor(v1, v2)
    end

    local Step = 0
    local result = 0

    v1 = math.modf(v1)
    v2 = math.modf(v2)
    while (v1 ~= 0 or  v2 ~= 0) do
        local r1 = v1 % 2
        local r2 = v2 % 2
        if r1 == 1 or r2 == 1 then
            result = result + math.pow(2, Step)
        else
            result = result + 0
        end

        Step = Step + 1
        v1 = math.RightMove(v1, 1)
        v2 = math.RightMove(v2, 1)
    end
    return result
end

math.BitEquationRightNumber = function(v1, v2)
    local BaseD = 0x80000000;

    for i = 1, 32 do
        if math.BitAnd(BaseD, v1) ~= math.BitAnd(BaseD, v2) then
            return i - 1
        else
            BaseD =  math.RightMove(BaseD, 1)
        end
    end

    return 32
end

math.MortonCode2 = function(x)
    x = math.BitAnd(0x0000ffff, x);
   
    x = math.BitAnd(math.BitXor(x, math.LeftMove(x, 8)), 0x00ff00ff);
    x = math.BitAnd(math.BitXor(x, math.LeftMove(x, 4)), 0x0f0f0f0f);
    x = math.BitAnd(math.BitXor(x, math.LeftMove(x, 2)), 0x33333333);
    x = math.BitAnd(math.BitXor(x, math.LeftMove(x, 1)), 0x55555555);

    return x
end

math.MortonCode3 = function(x)
    x = math.BitAnd(0x000003ff, x);

    x = math.BitAnd(math.BitXor(x, math.LeftMove(x, 16)), 0xff0000ff);
   
    x = math.BitAnd(math.BitXor(x, math.LeftMove(x, 8)), 0x0300f00f);
    x = math.BitAnd(math.BitXor(x, math.LeftMove(x, 4)), 0x030c30c3);
    x = math.BitAnd(math.BitXor(x, math.LeftMove(x, 2)), 0x09249249);

    return x
end

math.ReverseMortonCode2 = function( x )
    x = math.BitAnd(0x55555555, x);
    x = math.BitAnd(math.BitXor(x, math.RightMove(x, 1)), 0x33333333)
    x = math.BitAnd(math.BitXor(x, math.RightMove(x, 2)), 0x0f0f0f0f)
    x = math.BitAnd(math.BitXor(x, math.RightMove(x, 4)), 0x00ff00ff)
    x = math.BitAnd(math.BitXor(x, math.RightMove(x, 8)), 0x0000ffff)
    return x
end

math.ReverseMortonCode3 = function( x )
    x = math.BitAnd(0x09249249, x);

    x = math.BitAnd(math.BitXor(x, math.RightMove(x, 2)), 0x030c30c3)
    x = math.BitAnd(math.BitXor(x, math.RightMove(x, 4)), 0x0300f00f)
    x = math.BitAnd(math.BitXor(x, math.RightMove(x, 8)), 0xff0000ff)
    x = math.BitAnd(math.BitXor(x, math.RightMove(x, 16)), 0x000003ff)

    return x
end

math.AppendArray = function(DesArray, SourceArray)
    for i = 1, #SourceArray do
        DesArray[#DesArray + 1] = SourceArray[i]
    end
end

-- Encode for normal map.
math.SphericalEncode = function(v3)
    local v = Vector.new()
    v.x = math.atan2(v3.y, v3.x) * math.invc2pi
    v.y = v3.z

    v = v * 0.5 + 0.5
    return v
end

math.SphericalDecode = function(v)
    local ang = v * 2.0 - 1.0

    local scth = Vector.new()

    local r = ang.x * math.c2pi
    local d2 =  1.0 - ang.y * ang.y
     

    scth.x = math.cos(r)
    scth.y = math.sin(r)

    local schpi = Vector.new(math.sqrt( 1.0 - ang.y * ang.y ), ang.y)

    local v3 = Vector3.new(scth.x * schpi.x, scth.y * schpi.x, schpi.y)

    return v3
end

local OctWrap = function(v)
    local x = ( 1.0 - math.abs( v.x ) ) * ( v.x >= 0.0 and 1.0 or -1.0 );
    local y = ( 1.0 - math.abs( v.y ) ) * ( v.y >= 0.0 and 1.0 or -1.0 );
    return Vector.new(y, x)
end

math.OctEncode = function(v3)
    v3 = v3 / (math.abs(v3.x) + math.abs(v3.y) + math.abs(v3.z))

    local n = Vector.new(v3.x, v3.y)

    if v3.z < 0 then
        n = OctWrap(n)
    end

    n = n * 0.5 + 0.5
    return n
end

math.OctDecode = function(v)
    v = v * 2.0 - 1.0

    local n = Vector3.new(v.x, v.y, 1.0 - math.abs(v.x) - math.abs(v.y))
    local t = math.clamp(-n.z, 0, 1)
    n.x = n.x + (n.x > 0 and -t or t)
    n.y = n.y + (n.y > 0 and -t or t)

    return n:normalize()
end

math.ArrayAdd = function(a, b)
    _errorAssert(#a == #b, "math.AddArray")
    local Result = {}
    for i = 1, #a do
        Result[i] = a[i] + b[i]
    end
    return Result
end

math.ArraySub = function(a, b)
    _errorAssert(#a == #b, "math.ArraySub")
    local Result = {}
    for i = 1, #a do
        Result[i] = a[i] - b[i]
    end
    return Result
end

math.ArrayDiv = function(a, b)
    _errorAssert(#a > 0 and type(b) == 'number', "math.ArrayDiv")
    local Result = {}
    for i = 1, #a do
        Result[i] = b ~= 0 and a[i] / b or 0
    end

    return Result
end


math.ArrayMulValue = function(a, b)
    _errorAssert(#a > 0 and type(b) == 'number', "math.ArrayMulValue")
    local Result = {}
    for i = 1, #a do
        Result[i] = a[i] * b
    end
    return Result
end

math.ArraySize = function(a)
    _errorAssert(#a > 0, "math.ArraySize")
    local Result = 0
    for i = 1, #a do
        Result = Result + a[i] * a[i]
    end

    return math.sqrt(Result)
end

math.ArrayNormalize = function(a)
    _errorAssert(#a > 0, "math.ArraySize")
    local _Size = math.ArraySize(a)

    local Result = {}
    for i = 1, #a do
        Result[i] = a[i] / _Size
    end

    return Result
end

math.ArrayConvertMatrixsRow = function(v)
    _errorAssert(#v > 0, "math.ArrayConvertMatrixsRow")
    local m = #v
    local mat = Matrixs.new(m, m)
    for j = 1, mat.Column do
        mat[1][j] = v[j]
    end

    return mat
end

math.ArrayConvertMatrixsColumn = function(v)
    _errorAssert(#v > 0, "math.ArrayConvertMatrixsColumn")
    local m = #v
    local mat = Matrixs.new(m, m)
    for i = 1, mat.Row do
        mat[i][1] = v[i]
    end
    return mat
end

math.ArrayIdentity = function(v)
    _errorAssert(#v > 1, "math.ArrayIdentity")
    local Result = {}
    Result[1] = 1
    for i = 2, #v do
        Result[i] = 0
    end

    return Result
end

math.ArrayCopy = function(SourceArray, DesArray)
    for i, v in ipairs(SourceArray) do
        DesArray[i] = v
    end
end

math.IsNearlyEqual = function(A, B, SMALL_NUMBER)
    local ErrorTolerance = SMALL_NUMBER or math.SMALL_NUMBER
    return math.abs( A - B ) <= ErrorTolerance;
end

function IsValidUV(InUV, w, h)

	return InUV.x >= 0 and InUV.x <= w and InUV.y >= 0.0 and InUV.y <= h
end

--最大公约数
math.gcd = function(a, b)
    -- 处理负数
    a = math.abs(a)
    b = math.abs(b)
    
    -- 欧几里得算法
    while b ~= 0 do
        a, b = b, a % b
    end
    return a
end

--最小公倍数
math.lcm = function(a, b)
    -- 处理0的情况
    if a == 0 or b == 0 then
        return 0
    end
    
    -- 公式计算
    return math.abs(a * b) / math.gcd(a, b)
end

math.round2 = function(num, decimalPlaces)
    local mult = 10^(decimalPlaces or 6)
    if num >= 0 then
        return math.floor(num * mult + 0.5) / mult
    else
        return math.ceil(num * mult - 0.5) / mult
    end
end

math.UniformSampleSphere = function( E )

	local Phi = 2 * math.pi * E.x;
	local CosTheta = 1 - 2 * E.y;
	local SinTheta = math.sqrt( 1 - CosTheta * CosTheta );

	local H = Vector3.new();
	H.x = SinTheta * math.cos( Phi );
	H.y = SinTheta * math.sin( Phi );
	H.z = CosTheta;

	local PDF = 1.0 / (4 * math.pi);

	return Vector4.new( H.x, H.y, H.z, PDF );
end

math.MinNumber = 0.000001;
math.MaxNumber = 999999.0;
math.cEpsilon = 0.000001;

math.maxFloat	=  3.402823466e+38;
math.minFloat	= -3.402823466e+38;

math.KINDA_SMALL_NUMBER	 = 1.e-4
math.SMALL_NUMBER = 1.e-8

math.c2pi = math.pi * 2
math.invpi = 1 / math.pi
math.invc2pi = 1 / math.c2pi
-- math.ARC = math.PI * 2;
math.FLT_MAX = 3.402823466e+38
math.UE_KINDA_SMALL_NUMBER = 1.e-4