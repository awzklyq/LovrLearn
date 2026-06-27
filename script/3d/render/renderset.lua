_G.RenderSet = {}

local viewmatrixs = {}
local projectmatrixs = {}
RenderSet.pushViewMatrix = function(vm)
    table.insert(viewmatrixs, vm)
end

RenderSet.popViewMatrix = function()
    if  #viewmatrixs == 0 then return end
    table.remove(viewmatrixs, #viewmatrixs)
end

RenderSet.pushProjectMatrix = function(pm)
    table.insert(projectmatrixs, pm)
end

RenderSet.popProjectMatrix = function()
    if  #projectmatrixs == 0 then return end
    table.remove(projectmatrixs, #projectmatrixs)
end

RenderSet.getUseViewMatrix = function()
    if  #viewmatrixs == 0 then
        return RenderSet.getDefaultViewMatrix()
    end

    return viewmatrixs[#viewmatrixs]
end

RenderSet.getUseProjectMatrix = function()
    if  #projectmatrixs == 0 then
        return RenderSet.getDefaultProjectMatrix()
    end

    return projectmatrixs[#projectmatrixs]
end

RenderSet.getDefaultViewMatrix = function()
    local camera3d = _G.getGlobalCamera3D()
    -- return  Matrix3D.transpose(Matrix3D.createLookAtRH(camera3d.eye, camera3d.look, -camera3d.up))
    --return Matrix3D.getViewMatrix(camera3d.eye, camera3d.look, camera3d.up)
  return Matrix3D.transpose(Matrix3D.createLookAtRH(camera3d.eye, camera3d.look, -camera3d.up))
end

RenderSet.getDefaultProjectMatrix = function()
    local camera3d = _G.getGlobalCamera3D()
    -- return  Matrix3D.getProjectionMatrix(camera3d.fov, camera3d.nearClip, camera3d.farClip, camera3d.aspectRatio)
    return Matrix3D.createPerspectiveFovRH( camera3d.fov, camera3d.aspectRatio, camera3d.nearClip, camera3d.farClip )
end

RenderSet.getCameraFrustumViewMatrix = function()
    local camera3d = _G.getGlobalCamera3D()
    return Matrix3D.createLookAtLH(camera3d.eye, camera3d.look, camera3d.up)
end

RenderSet.getCameraFrustumProjectMatrix = function()
    local camera3d = _G.getGlobalCamera3D()
    -- return  Matrix3D.getProjectionMatrix(camera3d.fov, camera3d.nearClip, camera3d.farClip, camera3d.aspectRatio)
    return Matrix3D.createPerspectiveFovLH( camera3d.fov, camera3d.aspectRatio, camera3d.nearClip, camera3d.farClip )
end

local _Matrix2Ds = {}
RenderSet.PushMatrix2D = function(InMatrix2D)
    _Matrix2Ds[#_Matrix2Ds + 1] = InMatrix2D
end

RenderSet.PopMatrix2D = function()
    table.remove(_Matrix2Ds, #_Matrix2Ds)
end

RenderSet.UseMatrix2D = function()
    if #_Matrix2Ds > 0 then
        _Matrix2Ds[#_Matrix2Ds]:use()
    end
end

local _Matrix3Ds = {}
local _Matrix3D = Matrix3D.new()
RenderSet.PusMatrix3D = function(InMatrix3D)
    _Matrix3Ds[#_Matrix3Ds + 1] = InMatrix3D
end

RenderSet.PopMatrix3D = function()
    table.remove(_Matrix3Ds, #_Matrix3Ds)
end

RenderSet.UseMatrix3D = function()
    _Matrix3D:Identity()
    for i = 1, #_Matrix3Ds do
        _Matrix3D:mulRight(_Matrix3Ds[i])
    end
    return _Matrix3D
end

RenderSet.SetWireframe = function(...)
end

app.resizeWindow(function(w, h)

end)


RenderSet.screenwidth = lovr.system.getWindowWidth()
RenderSet.screenheight = lovr.system.getWindowHeight()
RenderSet.EnableScreenCull = true

-- ---------------------------------------------------------------------------
-- Screen-cull statistics
-- ---------------------------------------------------------------------------
-- Per-frame counters for how many primitive bounds were tested by
-- RenderSet.IsBoundsOutOfScreen and how many of those were actually culled.
-- The settings screen exposes a "Show Cull Stats" toggle (ShowCullStats)
-- that drives the on-screen overlay rendered by DrawCullStatsOverlay.
--
-- Lifecycle:
--   1. ResetCullStats() is called at the very start of each frame (app.render
--      callback in main.lua) so the counters measure exactly one frame.
--   2. IsBoundsOutOfScreen() increments CulledCount / TestedCount as shapes
--      go through the cull test.
--   3. DrawCullStatsOverlay() is called at the end of the frame (after all
--      world rendering and the scaling transform has been popped) so it
--      draws in raw pixel coordinates on top of everything.
RenderSet.ShowCullStats = false
RenderSet.CulledCount = 0
RenderSet.TestedCount = 0
-- Frozen snapshot of the counters from the previous frame. We display the
-- previous frame's numbers so that the overlay itself (drawn AFTER the cull
-- tests) doesn't skew its own reading, and so the overlay can render even
-- before the first frame's counters are complete.
RenderSet._lastCulledCount = 0
RenderSet._lastTestedCount = 0

RenderSet.ResetCullStats = function()
    RenderSet._lastCulledCount = RenderSet.CulledCount
    RenderSet._lastTestedCount = RenderSet.TestedCount
    RenderSet.CulledCount = 0
    RenderSet.TestedCount = 0
end

-- Screen-space bounds culling. The (minX, minY, maxX, maxY) rectangle is
-- specified in the caller's *local* coordinate space -- every shape in
-- script/polygon/*.lua passes its own self.x / self.y straight in. When the
-- caller drew inside a push/translate/scale/rotate block (e.g. the boss
-- preview panel, or any entity that push-translates onto its own position
-- before emitting primitives), those local coordinates do NOT describe
-- screen pixels at all, and comparing them with the raw screen width /
-- height misclassifies on-screen shapes as "offscreen" and culls them.
-- (This is why the Chinese Pavilion / Japanese Shrine / etc. previews lost
-- their roofs, lanterns, ridge beasts, couplet strips and upper tier when
-- EnableScreenCull was on: those primitives live at local y <~ -30 relative
-- to the boss origin, and the raw check saw maxY < 0 and dropped them.)
--
-- To keep the culling correct under arbitrary transforms, resolve the four
-- rectangle corners through the current love.graphics transform stack and
-- build the screen-space AABB from the transformed corners before comparing
-- with the viewport. (All four corners are needed because rotation /
-- non-uniform scale can swap min/max.)
RenderSet.IsBoundsOutOfScreen = function(minX, minY, maxX, maxY)
    if not RenderSet.EnableScreenCull then
        return false
    end
    RenderSet.TestedCount = RenderSet.TestedCount + 1
    local tp = love.graphics.transformPoint
    local x1, y1 = tp(minX, minY)
    local x2, y2 = tp(maxX, minY)
    local x3, y3 = tp(maxX, maxY)
    local x4, y4 = tp(minX, maxY)
    local sMinX = x1; if x2 < sMinX then sMinX = x2 end
    if x3 < sMinX then sMinX = x3 end
    if x4 < sMinX then sMinX = x4 end
    local sMaxX = x1; if x2 > sMaxX then sMaxX = x2 end
    if x3 > sMaxX then sMaxX = x3 end
    if x4 > sMaxX then sMaxX = x4 end
    local sMinY = y1; if y2 < sMinY then sMinY = y2 end
    if y3 < sMinY then sMinY = y3 end
    if y4 < sMinY then sMinY = y4 end
    local sMaxY = y1; if y2 > sMaxY then sMaxY = y2 end
    if y3 > sMaxY then sMaxY = y3 end
    if y4 > sMaxY then sMaxY = y4 end
    local sw = RenderSet.screenwidth
    local sh = RenderSet.screenheight
    local outside = sMaxX < 0 or sMinX > sw or sMaxY < 0 or sMinY > sh
    if outside then
        RenderSet.CulledCount = RenderSet.CulledCount + 1
    end
    return outside
end

RenderSet.isNeedFrustum = true
RenderSet.AlphaTestBlend = 0.5
RenderSet.AlphaTestMode = 2
RenderSet.frameToken = 1
RenderSet.FrameInterval = 0

RenderSet.HDR = false

RenderSet.EnableCDLOD = true


RenderSet.LOD1Distance = 300
RenderSet.LOD2Distance = 500
RenderSet.LOD3Distance = 800

RenderSet.ESM_C = 10
RenderSet.EnableESM = false
