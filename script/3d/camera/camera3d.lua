_G.Camera3D = {}
function Camera3D.new(x1, y1, x2, y2, lw)-- lw :line width
    local camera = setmetatable({}, {__index = Camera3D});

    camera.fov = math.pi/2
    camera.nearClip = 1
    camera.farClip = 50000
    camera.aspectRatio = lovr.system.getWindowWidth()/lovr.system.getWindowHeight()

    camera.eye = Vector3.new(0,0,0)

    camera.up = Vector3.new(0,0,1)

    camera.look = Vector3.new(0,0,-1)

    camera.renderid = Render.Camera3DId
    
    return camera;
end

function Camera3D:getPhi( )

    return ( Vector3.sub(self.eye, self.look) ):Cartesian2Spherical( ).z;
end

function Camera3D:getTheta( )
    return ( Vector3.sub(self.eye, self.look) ):Cartesian2Spherical( ).y;
end

function Camera3D:getRadius( )
    return Vector3.distance(self.eye, self.look)
end

function Camera3D:movePhi( phi )

	if phi == 0 then
        return;
    end

    local curPhi = self:getPhi()

    if  curPhi + phi < math.MinNumber  then
        phi = math.MinNumber - curPhi;
    elseif  curPhi + phi >math.MaxNumber  then
        phi = math.MaxNumber - curPhi;
    end
                
    local temp = curPhi + phi;
	while ( temp > math.c2pi ) do
        temp = temp - math.c2pi;
    end

    while ( temp < 0 ) do
        temp = temp + math.c2pi;
    end

    if  temp < math.MinNumber and temp > math.MaxNumber then
    
        if  math.abs( curPhi - math.MinNumber ) < math.abs( curPhi - math.MaxNumber ) then
            phi = math.MinNumber - curPhi;--mPhiLimit.x
        else
            phi = math.MaxNumber - curPhi;--mPhiLimit.y
        end
    end

    local mat = Matrix3D.new()
    mat:mulTranslationRight(-self.look.x, -self.look.y, -self.look.z)
    mat:mulRotationRight(self.up.x, self.up.y, self.up.z, phi)
    mat:mulTranslationRight(self.look.x, self.look.y, self.look.z)

    self.eye = mat:mulLeftVector3(self.eye, true)
end

function Camera3D:moveTheta( theta)
	if ( theta == 0.0 ) then
        return;
    end

    local temp = self:getTheta( );
    if ( temp - theta < math.MinNumber) then
        theta = temp - math.MinNumber;
    elseif ( temp - theta > math.MaxNumber ) then
        theta = temp - math.MaxNumber;
    end
            

    local right = Vector3.cross( self.up, Vector3.sub(self.look, self.eye) )
    right:normalize( )

	local vec1 = Vector3.cross( Vector3.sub(self.eye, self.look), right );

    local mat = Matrix3D.new()
    mat:mulTranslationRight(-self.look.x, -self.look.y, -self.look.z)
    mat:mulRotationRight(right.x, right.y, right.z, theta)
    mat:mulTranslationRight(self.look.x, self.look.y, self.look.z)

    local eye = mat:mulLeftVector3(self.eye, true);
	local vec2 = Vector3.cross( Vector3.sub(self.eye, self.look), right );

	if ( Vector3.dot( vec1, self.up ) * Vector3.dot( vec2, self.up ) < 0.0 ) then
        self.up = Vector3.new(-self.up.x, -self.up.y, -self.up.z)
    end

	self.eye = eye
end

function Camera3D:moveRadius( radius)
	if ( radius == 0.0 ) then
        return;
    end

	if self.eye:equal(self.look ) then
        return;
    end

    local dir = Vector3.sub(self.eye, self.look)
    dir:normalize()
	self.eye = Vector3.add(self.eye, dir:mul(radius))
end

function Camera3D:GetDirction()
    local dir = Vector3.sub(self.look, self.eye)
    -- return dir:normalize()
    return dir:normalize() 
end

-- give the camera a point to look from and a point to look towards
function Camera3D:setCameraAndLookAt(x,y,z, xAt,yAt,zAt)
    self.eye:setXYZ(x,y,z)
    self.look:setXYZ(xAt,yAt,zAt)

    -- update the camera in the shader
    -- CameraShader:send("viewMatrix", GetViewMatrix(Camera.position, Camera.look, Camera.up))
end

_G.currentCamera3D = Camera3D.new()
_G.getGlobalCamera3D = function()
    return _G.currentCamera3D
end
_G.setGlobalCamera3D = function(camera)
    _G.currentCamera3D = camera
end

--------------------- camera3d control
-- Mouse state
local mouse = {mousex = 0, mousey = 0}

-- Helper: translate both eye and look by a world-space delta vector
local function translateCamera(cam, delta)
    cam.eye  = Vector3.new(cam.eye.x  + delta.x, cam.eye.y  + delta.y, cam.eye.z  + delta.z)
    cam.look = Vector3.new(cam.look.x + delta.x, cam.look.y + delta.y, cam.look.z + delta.z)
end

-- Mouse move:
--   Left button drag          -> orbit (rotate around look target)
--   Middle button + Alt drag  -> orbit (rotate around look target)
--   Middle button drag        -> pan (translate eye & look)
--   Right button drag         -> pan up/down/left/right (translate eye & look)
app.mousemoved(function(x, y, dx, dy, istouch)
    local cam = _G.currentCamera3D

    -- Orbit: left mouse button  OR  middle button + Alt
    local isOrbit = lovr.system.isMouseDown(1) or
                    (lovr.system.isMouseDown(3) and lovr.system.isKeyDown("lalt"))
    if isOrbit then
        cam:movePhi(  -(mouse.mousex - x) * 0.005)
        cam:moveTheta( (mouse.mousey - y) * 0.005)
    -- Pan: right mouse button OR middle mouse button (without Alt)
    elseif lovr.system.isMouseDown(2) or lovr.system.isMouseDown(3) then
        local dir = Vector3.sub(cam.look, cam.eye)
        local vx = Vector3.cross(dir, cam.up)
        vx:normalize()
        local vy = Vector3.cross(dir, vx)
        vy:normalize()
        local scale = dir:distanceself() / cam.nearClip * 0.001
        local nearx = Vector3.mul(vx, -(mouse.mousex - x) * scale)
        local neary = Vector3.mul(vy,  (mouse.mousey - y) * scale)
        local move  = Vector3.add(nearx, neary)
        translateCamera(cam, move)
    end

    mouse.mousex = x
    mouse.mousey = y
end)

app.wheelmoved(function(x, y)
    _G.currentCamera3D:moveRadius(y * -0.1 * _G.currentCamera3D:getRadius())
end)

-- Keyboard control (called every frame from app.update)
-- W/S or Up/Down  -> move forward / backward along look direction
-- A/D or Left/Right -> strafe left / right
-- E/Q             -> move up / down along world up axis
-- Shift           -> speed boost (x5)
-- R               -> reset camera to default position
local _cameraKeySpeed = 50.0  -- units per second

app.update(function(dt)
    local cam = _G.currentCamera3D
    local speed = _cameraKeySpeed * (lovr.system.isKeyDown("lshift") and 5.0 or 1.0)
    local step  = speed * dt

    -- Forward direction (horizontal, ignoring vertical component for FPS-style)
    local forward = Vector3.sub(cam.look, cam.eye)
    forward:normalize()

    -- Right direction
    local right = Vector3.cross(forward, cam.up)
    right:normalize()

    -- Up direction (world up)
    local up = Vector3.new(0, 1, 0)

    local move = Vector3.new(0, 0, 0)

    -- Forward / Backward
    if lovr.system.isKeyDown("w") or lovr.system.isKeyDown("up") then
        move = Vector3.add(move, Vector3.mul(forward, step))
    end
    if lovr.system.isKeyDown("s") or lovr.system.isKeyDown("down") then
        move = Vector3.add(move, Vector3.mul(forward, -step))
    end

    -- Strafe Left / Right
    if lovr.system.isKeyDown("a") or lovr.system.isKeyDown("left") then
        move = Vector3.add(move, Vector3.mul(right, -step))
    end
    if lovr.system.isKeyDown("d") or lovr.system.isKeyDown("right") then
        move = Vector3.add(move, Vector3.mul(right, step))
    end

    -- Up / Down
    if lovr.system.isKeyDown("e") then
        move = Vector3.add(move, Vector3.mul(up, step))
    end
    if lovr.system.isKeyDown("q") then
        move = Vector3.add(move, Vector3.mul(up, -step))
    end

    if move.x ~= 0 or move.y ~= 0 or move.z ~= 0 then
        translateCamera(cam, move)
    end
end)



