_G.Mesh = {}

-- Profiler (optional) for measuring how long it takes each CollectXXXMesh
-- variant to build its vertex buffer every frame. Requiring it lazily /
-- guarded so the polygon module stays usable in unit tests that don't pull
-- in the vampire demo tree.
local _ProfilerOk, _Profiler = pcall(require, "script.demo.vampire.profiler")
if not _ProfilerOk then _Profiler = nil end

local function _profBegin(label)
    if _Profiler and _Profiler.begin then
        return _Profiler.begin(label)
    end
    return nil
end

local function _profEnd(finish)
    if finish then finish() end
end


local vertexFormat = {
    {"VertexPosition", "float", 2},
    {"VertexTexCoord", "float", 2},
    {"VertexColor", "float", 4},--normal
    -- {"ConstantColor", "byte", 4},
}

function Mesh.new(vertices, mode, usage)
    local mesh = setmetatable({}, Mesh);
    -- mesh.obj = love.graphics.newMesh(vertices, mode, usage)
    mesh.obj = love.graphics.newMesh(vertexFormat, vertices, mode or "fan")

    mesh.transform = Matrix.new()
    mesh.renderid = Render.MeshId ;
    return mesh
end

Mesh.__index = function(tab, key, ...)
    local value = rawget(tab, key);
    if value then
        return value;
    end

    if Mesh[key] then
        return Mesh[key];
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

Mesh.__newindex = function(tab, key, value)
    rawset(tab, key, value);
end

function Mesh:setCanvas(canvas)
    self:setTexture(canvas.obj)
end

function Mesh:Flush()
    self:flush()
end

-- Mesh:setVertex( index, x, y, u, v, r, g, b, a )

function Mesh:SetVertex(InIndex, InData)
    self:setVertex( InIndex, InData[1], InData[2], InData[3], InData[4], InData[5], InData[6], InData[7], InData[8])

    -- self:Flush()
end

function Mesh:setBaseTexture(canvas)
    if not canvas then
        self.shader = Shader.GetBaseShader()
    else
        self.shader = Shader.GetBaseImageShader()
        self.shader:setBaseImage(canvas.obj)
    end
end


function Mesh:draw()
    if self.UpdateShaderValue then
        self:UpdateShaderValue()
    end
    Render.RenderObject(self);
end

Mesh.CreteMeshFormSimpleConcavePolygon = function(vertices, ...)
    local num = #vertices

    local colors = {...}
    local minx, miny, maxx, maxy = 0, 0, 0, 0
    for i = 1, num, 2 do
        minx = math.min(minx,  vertices[i])
        miny = math.min(miny,  vertices[i +1])

        maxx = math.max(maxx,  vertices[i])
        maxy = math.max(maxy,  vertices[i +1])
    end

    local datas = {}
    for i = 1, #vertices, 2 do
        local color = colors[i % #colors + 1]
        if #colors == 1 then
            color = colors[1]
        end
        table.insert(datas, {vertices[i], vertices[i +1], -- position of the vertex
        (vertices[i] - minx) / (maxx - minx), (vertices[i + 1] - miny) / (maxy - miny), -- texture coordinate at the vertex position
        color._r, color._g, color._b, color._a})
    end

    return Mesh.new(datas);
end

_G.MeshQuad = {}

_G.MeshQuad.new = function(w, h, color, img)
    -- local vertices = {-w * 0.5, -h * 0.5, 
    -- w * 0.5, -h * 0.5,
    -- w * 0.5, h * 0.5,
    -- -w * 0.5, h * 0.5};

    local vertices = {0 , 0 , 
    0 , h ,
    w , h ,
    w , 0 };

    local mesh = Mesh.CreteMeshFormSimpleConcavePolygon(vertices, color);
    if img then
        if img.obj then
            mesh:setTexture(img.obj)
        else
            mesh:setTexture(img)
        end
        
    end

    mesh.shader = Shader.GetBaseShader()

    return mesh;
end

_G.MeshQuadBlur = {}

_G.MeshQuadBlur.new = function(w, h, color)
    -- local vertices = {-w * 0.5, -h * 0.5, 
    -- w * 0.5, -h * 0.5,
    -- w * 0.5, h * 0.5,
    -- -w * 0.5, h * 0.5};

    local vertices = {0 , 0 , 
    0 , h ,
    w , h ,
    w , 0 };

    local mesh = Mesh.CreteMeshFormSimpleConcavePolygon(vertices, color);

    mesh.shader = Shader.GetImageBlurShader()

    mesh.BindImage = function(obj, img, imgw, imgh)
        obj.image = img
        obj.imgw = imgw or  obj.image.w
        obj.imgh = imgh or  obj.image.h   
    end

    mesh.UpdateShaderValue = function(obj)
        obj.shader:SetImageBlurShader(obj.image.obj, obj.imgw, obj.imgh, obj.BlurSizeX / obj.imgw ,  obj.BlurSizeY / obj.imgh ,  (obj.BlurSizeX + obj.BlurSizeW) / obj.imgw, (obj.BlurSizeY + obj.BlurSizeH) / obj.imgh, obj.offset, obj.blurnum, obj.power)
    end

    mesh.BlurSize = function(obj, x, y, w, h)
        obj.BlurSizeX = x or 0
        obj.BlurSizeY = y or 0
        obj.BlurSizeW = w or obj.imgw
        obj.BlurSizeH = h or obj.imgh
    end

    return mesh;
end


_G.MeshGrids = {}

_G.MeshGrids.new = function(InStartX, InStartY, w, h, wn, hn, color, img, InFunc)
    -- local vertices = {-w * 0.5, -h * 0.5, 
    -- w * 0.5, -h * 0.5,
    -- w * 0.5, h * 0.5,
    -- -w * 0.5, h * 0.5};

    local _OffsetX = w / wn
    local _OffsetY = h / hn

    local _StartX = InStartX
    local _StartY = InStartY
    local _AllVertices = {}
    local _AllUVs = {}
    local Indexs = {}
    for i = 1, wn do
        for j = 1, hn do
            local vertices = {0 , 0 , 
            0 , h ,
            w , h ,
            w , 0 };

            local sx = _StartX + (i - 1) * _OffsetX
            local sy = _StartY + (j - 1) * _OffsetY

            local v1 = {sx, sy}
            local v2 = {sx, sy + _OffsetY}
            local v3 = {sx + _OffsetX, sy + _OffsetY}

            local v4 = {sx, sy}
            local v5 = {sx + _OffsetX, sy + _OffsetY}
            local v6 = {sx + _OffsetX, sy}

            _AllVertices[#_AllVertices + 1] = v1
            _AllVertices[#_AllVertices + 1] = v2
            _AllVertices[#_AllVertices + 1] = v3

            _AllVertices[#_AllVertices + 1] = v4
            _AllVertices[#_AllVertices + 1] = v5
            _AllVertices[#_AllVertices + 1] = v6

            local index1 = {i, j}
            local index2 = {i, j + 1}
            local index3 = {i + 1, j + 1}

            local index4 = {i, j}
            local index5 = {i + 1, j + 1}
            local index6 = {i + 1, j}

            Indexs[#Indexs + 1] = index1
            Indexs[#Indexs + 1] = index2
            Indexs[#Indexs + 1] = index3

            Indexs[#Indexs + 1] = index4
            Indexs[#Indexs + 1] = index5
            Indexs[#Indexs + 1] = index6

            local uv1 = {(v1[1] - _StartX) / w, (v1[2] - _StartY) / h }
            local uv2 = {(v2[1] - _StartX) / w, (v2[2] - _StartY) / h }
            local uv3 = {(v3[1] - _StartX) / w, (v3[2] - _StartY) / h }
            local uv4 = {(v4[1] - _StartX) / w, (v4[2] - _StartY) / h }
            local uv5 = {(v5[1] - _StartX) / w, (v5[2] - _StartY) / h }
            local uv6 = {(v6[1] - _StartX) / w, (v6[2] - _StartY) / h }

            _AllUVs[#_AllUVs + 1] = uv1
            _AllUVs[#_AllUVs + 1] = uv2
            _AllUVs[#_AllUVs + 1] = uv3

            _AllUVs[#_AllUVs + 1] = uv4
            _AllUVs[#_AllUVs + 1] = uv5
            _AllUVs[#_AllUVs + 1] = uv6

        end
    end
    
    
    local _Datas = {}
    for i = 1, #_AllVertices do
        local _Data = {}
        _Data[#_Data + 1] = _AllVertices[i][1]
        _Data[#_Data + 1] = _AllVertices[i][2]

        _Data[#_Data + 1] = _AllUVs[i][1]
        _Data[#_Data + 1] = _AllUVs[i][2]

        _Data[#_Data + 1] = color._r
        _Data[#_Data + 1] = color._g
        _Data[#_Data + 1] = color._b
        _Data[#_Data + 1] = color._a

        if InFunc then
            InFunc(#_Datas + 1, Indexs[i][1], Indexs[i][2], _Data, _AllVertices[i][1], _AllVertices[i][2])
        end
        _Datas[#_Datas + 1] = _Data
    end

    local mesh = Mesh.new(_Datas, "triangles");
    if img then
        if img.obj then
            mesh:setTexture(img.obj)
        else
            mesh:setTexture(img)
        end
        
    end

    mesh.shader = Shader.GetBaseShader()

    return mesh;
end

-- =============================================================================
-- CollectCirclesMesh
-- -----------------------------------------------------------------------------
-- A dynamic triangle-mesh that batches a set of Circle objects into a single
-- draw call. The vertex buffer is expected to be rewritten every frame via
-- SetCircles(circles); the mesh is built with "dynamic" usage so the GPU
-- buffer is cheap to update.
--
-- Each Circle is tessellated into `seg` fan triangles (3 vertices each)
-- matching the visual of love.graphics.circle("fill", x, y, r, seg).
-- Vertex data layout follows Mesh.vertexFormat:
--   {VertexPosition(x,y), VertexTexCoord(u,v), VertexColor(r,g,b,a)}
-- where (u,v) is the point's normalized position inside the circle's AABB.
-- =============================================================================

_G.CollectCirclesMesh = {}
CollectCirclesMesh.__index = CollectCirclesMesh

-- Default segment count used when a Circle does not specify its own.
CollectCirclesMesh.DefaultSeg = 24

-- Pre-allocated vertex capacity so that hot-path updates can reuse the mesh.
CollectCirclesMesh.InitialCapacity = 256 * 3

local function _newBackingMesh(vertexCount)
    -- Build a dummy vertex list to size the mesh; contents get overwritten
    -- immediately by the first SetCircles call.
    local dummy = {}
    for i = 1, vertexCount do
        dummy[i] = {0, 0, 0, 0, 1, 1, 1, 0}
    end
    return love.graphics.newMesh(vertexFormat, dummy, "triangles", "dynamic")
end

function CollectCirclesMesh.new(initialCapacity)
    local self = setmetatable({}, CollectCirclesMesh)

    self.capacity = math.max(3, initialCapacity or CollectCirclesMesh.InitialCapacity)
    self.vertexCount = 0
    -- Reusable vertex buffer (array of {x,y,u,v,r,g,b,a}) to avoid GC.
    self.vertices = {}

    self.obj = _newBackingMesh(self.capacity)
    -- Clear the draw range; love.graphics.Mesh:setDrawRange() with no args
    -- means "draw nothing / whole mesh default". Passing (0, 0) raises
    -- "Invalid draw range." in LOVE 11.
    self.obj:setDrawRange()

    self.transform = Matrix.new()
    self.renderid = Render.MeshId

    self.Visible = true

    return self
end

-- Sets the list of Circle objects to be rendered this frame and rebuilds the
-- vertex buffer in-place. `circles` is an array of Circle instances (see
-- script/polygon/circle.lua). Circles whose Visible flag is false are
-- skipped.
function CollectCirclesMesh:SetCircles(circles)
    local __pf = _profBegin("Mesh.SetCircles")
    local verts = self.vertices
    local vi = 0

    if circles and #circles > 0 then
        for ci = 1, #circles do
            local c = circles[ci]
            if c and c.Visible ~= false and c.r and c.r > 0 then
                local cx, cy, r = c.x or 0, c.y or 0, c.r
                local seg = c.seg or CollectCirclesMesh.DefaultSeg
                if seg < 3 then seg = 3 end

                local col = c.color
                local cr, cg, cb, ca
                if col then
                    cr, cg, cb, ca = col._r or 1, col._g or 1, col._b or 1, col._a or 1
                else
                    cr, cg, cb, ca = 1, 1, 1, 1
                end

                local step = (2 * math.pi) / seg
                -- Center vertex data (reused across this circle's triangles)
                -- Pre-compute first edge point so each triangle is
                -- (center, prev, next) rather than recomputing both ends.
                local a0 = 0
                local px = cx + r * math.cos(a0)
                local py = cy + r * math.sin(a0)

                for i = 1, seg do
                    local a1 = i * step
                    local nx = cx + r * math.cos(a1)
                    local ny = cy + r * math.sin(a1)

                    -- Triangle: center, (px,py), (nx,ny)
                    vi = vi + 1
                    local v = verts[vi]
                    if not v then v = {}; verts[vi] = v end
                    v[1] = cx; v[2] = cy
                    v[3] = 0.5; v[4] = 0.5
                    v[5] = cr; v[6] = cg; v[7] = cb; v[8] = ca

                    vi = vi + 1
                    v = verts[vi]
                    if not v then v = {}; verts[vi] = v end
                    v[1] = px; v[2] = py
                    v[3] = (px - cx) / (2 * r) + 0.5
                    v[4] = (py - cy) / (2 * r) + 0.5
                    v[5] = cr; v[6] = cg; v[7] = cb; v[8] = ca

                    vi = vi + 1
                    v = verts[vi]
                    if not v then v = {}; verts[vi] = v end
                    v[1] = nx; v[2] = ny
                    v[3] = (nx - cx) / (2 * r) + 0.5
                    v[4] = (ny - cy) / (2 * r) + 0.5
                    v[5] = cr; v[6] = cg; v[7] = cb; v[8] = ca

                    px, py = nx, ny
                end
            end
        end
    end

    -- Trim any leftover entries from previous (larger) frames so setVertices
    -- does not accidentally push stale data.
    for i = #verts, vi + 1, -1 do
        verts[i] = nil
    end

    self.vertexCount = vi

    if vi == 0 then
        -- No circles to draw this frame; clear the range instead of passing
        -- (0, 0) which LOVE rejects as an invalid draw range.
        self.obj:setDrawRange()
        _profEnd(__pf)
        return
    end

    -- Grow backing mesh if needed (doubling strategy).
    if vi > self.capacity then
        local newCap = self.capacity
        while newCap < vi do newCap = newCap * 2 end
        self.capacity = newCap
        self.obj:release()
        self.obj = _newBackingMesh(newCap)
    end

    self.obj:setVertices(verts)
    self.obj:setDrawRange(1, vi)
    _profEnd(__pf)
end

function CollectCirclesMesh:setTexture(tex)
    if tex and tex.obj then
        self.obj:setTexture(tex.obj)
    else
        self.obj:setTexture(tex)
    end
end

function CollectCirclesMesh:setCanvas(canvas)
    self:setTexture(canvas)
end

function CollectCirclesMesh:getVertexCount()
    return self.vertexCount
end

function CollectCirclesMesh:draw()
    if not self.Visible then return end
    if self.vertexCount <= 0 then return end

    if self.UpdateShaderValue then
        self:UpdateShaderValue()
    end

    Render.RenderObject(self)
end

-- =============================================================================
-- BatchDraw
-- -----------------------------------------------------------------------------
-- Master switch controlling whether polygon primitives (Circle / Rect / Line /
-- Ellipse / Polygon) route their draw() through the per-frame batching
-- collectors registered below, or fall back to the original immediate
-- Render.RenderObject() path.
--
-- Use:
--   BatchDraw.SetEnabled(true|false) -- toggle whole system
--   BatchDraw.IsEnabled()            -- query current state
-- =============================================================================
_G.BatchDraw = _G.BatchDraw or {}
BatchDraw._enabled = true
BatchDraw._flushCallbacks = BatchDraw._flushCallbacks or {}

function BatchDraw.SetEnabled(v)
    BatchDraw._enabled = v and true or false
end

function BatchDraw.IsEnabled()
    return BatchDraw._enabled
end

-- Register a per-frame flush callback. Callbacks are invoked in registration
-- order by BatchDraw.Flush(), which should be called **while the game-world
-- camera transform is still active** (i.e. inside CameraManager.begineDraw /
-- endDraw). Each polygon module (circle/rect/line/ellipse/polygon) registers
-- a single callback that uploads its pending list to its collector mesh,
-- draws it and clears the pending list.
function BatchDraw.RegisterFlush(fn)
    if type(fn) ~= "function" then return end
    BatchDraw._flushCallbacks[#BatchDraw._flushCallbacks + 1] = fn
end

function BatchDraw.Flush()
    if not BatchDraw._enabled then return end
    -- CRITICAL: every collector (Circle / Ellipse / Rect / Line / Polygon)
    -- snapshots primitives in WORLD/SCREEN space - the snapshot's x/y are
    -- the result of `love.graphics.transformPoint()` evaluated at the time
    -- `:draw()` was called, and the size fields (r, rx/ry, w/h, ...) are
    -- already baked with the corresponding effective scale. The collector
    -- meshes are then expected to render under an IDENTITY transform.
    --
    -- Most call-sites correctly invoke Flush() AFTER popping their own
    -- push/scale block (see application.lua's love.draw, which flushes
    -- after _G.app.render returns). However a handful of in-game UI
    -- helpers (e.g. tower_hud's `withImmediateDraw`) call Flush() while
    -- the gameDraw push/translate/scale stack is still active so they
    -- can switch to immediate-mode rendering on top of the world. If the
    -- pending list contained primitives whose snapshots already carry
    -- the world transform baked in, drawing them while that same
    -- transform is still on the matrix stack would apply it a SECOND
    -- time - which is exactly the "monster / player rendered far away
    -- from their logical position" bug observed in-game.
    --
    -- Forcefully reset to identity for the duration of the flush so the
    -- collector meshes always see the same transform state regardless of
    -- when Flush() was triggered. Restored via push/pop so the caller's
    -- transform is left untouched.
    love.graphics.push()
    love.graphics.origin()
    local cbs = BatchDraw._flushCallbacks
    for i = 1, #cbs do
        cbs[i]()
    end
    love.graphics.pop()
end

-- ---------------------------------------------------------------------------
-- Shared helper: build a dummy backing mesh sized for `vertexCount` vertices
-- with triangles topology + dynamic usage (same pattern as _newBackingMesh
-- used for circles). Kept separate so rect/line/ellipse/polygon collectors
-- can size independently.
-- ---------------------------------------------------------------------------
local function _newTriBackingMesh(vertexCount)
    local dummy = {}
    for i = 1, vertexCount do
        dummy[i] = {0, 0, 0, 0, 1, 1, 1, 0}
    end
    return love.graphics.newMesh(vertexFormat, dummy, "triangles", "dynamic")
end

local function _writeVertex(verts, vi, x, y, u, v, r, g, b, a)
    local t = verts[vi]
    if not t then t = {}; verts[vi] = t end
    t[1] = x; t[2] = y
    t[3] = u; t[4] = v
    t[5] = r; t[6] = g; t[7] = b; t[8] = a
    return vi
end

-- =============================================================================
-- CollectRectsMesh
-- -----------------------------------------------------------------------------
-- Batches filled Rect instances into a single triangle mesh (2 triangles per
-- rect). Line-mode rects / rects with an image / rects whose color is nil are
-- left to the immediate path.
-- =============================================================================
_G.CollectRectsMesh = {}
CollectRectsMesh.__index = CollectRectsMesh
CollectRectsMesh.InitialCapacity = 256 * 6 -- 6 verts per rect

function CollectRectsMesh.new(initialCapacity)
    local self = setmetatable({}, CollectRectsMesh)
    self.capacity = math.max(6, initialCapacity or CollectRectsMesh.InitialCapacity)
    self.vertexCount = 0
    self.vertices = {}
    self.obj = _newTriBackingMesh(self.capacity)
    self.obj:setDrawRange()
    self.transform = Matrix.new()
    self.renderid = Render.MeshId
    self.Visible = true
    return self
end

function CollectRectsMesh:SetRects(rects)
    local __pf = _profBegin("Mesh.SetRects")
    local verts = self.vertices
    local vi = 0

    if rects and #rects > 0 then
        for ri = 1, #rects do
            local r = rects[ri]
            if r and r.w and r.h and r.w > 0 and r.h > 0 then
                local col = r.color
                local cr, cg, cb, ca
                if col then
                    cr, cg, cb, ca = col._r or 1, col._g or 1, col._b or 1, col._a or 1
                else
                    cr, cg, cb, ca = 1, 1, 1, 1
                end

                local x1, y1 = r.x or 0, r.y or 0
                local x2, y2 = x1 + r.w, y1 + r.h

                -- Triangle 1: (x1,y1) (x2,y1) (x2,y2)
                vi = vi + 1; _writeVertex(verts, vi, x1, y1, 0, 0, cr, cg, cb, ca)
                vi = vi + 1; _writeVertex(verts, vi, x2, y1, 1, 0, cr, cg, cb, ca)
                vi = vi + 1; _writeVertex(verts, vi, x2, y2, 1, 1, cr, cg, cb, ca)
                -- Triangle 2: (x1,y1) (x2,y2) (x1,y2)
                vi = vi + 1; _writeVertex(verts, vi, x1, y1, 0, 0, cr, cg, cb, ca)
                vi = vi + 1; _writeVertex(verts, vi, x2, y2, 1, 1, cr, cg, cb, ca)
                vi = vi + 1; _writeVertex(verts, vi, x1, y2, 0, 1, cr, cg, cb, ca)
            end
        end
    end

    for i = #verts, vi + 1, -1 do verts[i] = nil end
    self.vertexCount = vi

    if vi == 0 then
        self.obj:setDrawRange()
        _profEnd(__pf)
        return
    end

    if vi > self.capacity then
        local newCap = self.capacity
        while newCap < vi do newCap = newCap * 2 end
        self.capacity = newCap
        self.obj:release()
        self.obj = _newTriBackingMesh(newCap)
    end

    self.obj:setVertices(verts)
    self.obj:setDrawRange(1, vi)
    _profEnd(__pf)
end

function CollectRectsMesh:draw()
    if not self.Visible then return end
    if self.vertexCount <= 0 then return end
    Render.RenderObject(self)
end

-- =============================================================================
-- CollectLinesMesh
-- -----------------------------------------------------------------------------
-- Batches Line segments. Each line is expanded into a thin quad (2 triangles)
-- whose width matches the line's `lw`. This is an approximation of
-- love.graphics.line() with a given line width; it does not emulate line caps
-- or joins beyond simple rectangular stubs, which is the same visual that
-- love.graphics.line produces for short independent segments at moderate
-- widths.
-- =============================================================================
_G.CollectLinesMesh = {}
CollectLinesMesh.__index = CollectLinesMesh
CollectLinesMesh.InitialCapacity = 256 * 6 -- 6 verts per line segment

function CollectLinesMesh.new(initialCapacity)
    local self = setmetatable({}, CollectLinesMesh)
    self.capacity = math.max(6, initialCapacity or CollectLinesMesh.InitialCapacity)
    self.vertexCount = 0
    self.vertices = {}
    self.obj = _newTriBackingMesh(self.capacity)
    self.obj:setDrawRange()
    self.transform = Matrix.new()
    self.renderid = Render.MeshId
    self.Visible = true
    return self
end

-- Appends a single segment (x1,y1)->(x2,y2) with width lw and color rgba to
-- the vertex buffer starting at `vi`. Returns the new `vi`.
local function _pushLineSegment(verts, vi, x1, y1, x2, y2, lw, cr, cg, cb, ca)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 0.00001 then return vi end
    local hw = (lw or 2) * 0.5
    -- Unit perpendicular vector.
    local nx = -dy / len * hw
    local ny =  dx / len * hw

    local ax, ay = x1 + nx, y1 + ny
    local bx, by = x1 - nx, y1 - ny
    local cx, cy = x2 - nx, y2 - ny
    local ex, ey = x2 + nx, y2 + ny

    -- Tri 1: a, b, c
    vi = vi + 1; _writeVertex(verts, vi, ax, ay, 0, 0, cr, cg, cb, ca)
    vi = vi + 1; _writeVertex(verts, vi, bx, by, 0, 1, cr, cg, cb, ca)
    vi = vi + 1; _writeVertex(verts, vi, cx, cy, 1, 1, cr, cg, cb, ca)
    -- Tri 2: a, c, e
    vi = vi + 1; _writeVertex(verts, vi, ax, ay, 0, 0, cr, cg, cb, ca)
    vi = vi + 1; _writeVertex(verts, vi, cx, cy, 1, 1, cr, cg, cb, ca)
    vi = vi + 1; _writeVertex(verts, vi, ex, ey, 1, 0, cr, cg, cb, ca)
    return vi
end

-- `lines` may contain entries of two shapes:
--   * a Line object (uses .x1/.y1/.x2/.y2 via its metatable and .lw/.color)
--   * a Lines object (Render.LinesId) storing a polyline in .values
function CollectLinesMesh:SetLines(lines)
    local __pf = _profBegin("Mesh.SetLines")
    local verts = self.vertices
    local vi = 0

    if lines and #lines > 0 then
        for li = 1, #lines do
            local ln = lines[li]
            if ln then
                local col = ln.color
                local cr, cg, cb, ca
                if col then
                    cr, cg, cb, ca = col._r or 1, col._g or 1, col._b or 1, col._a or 1
                else
                    cr, cg, cb, ca = 1, 1, 1, 1
                end
                local lw = ln.lw or 2

                if ln.renderid == Render.LinesId then
                    -- Polyline: chain of connected segments.
                    local vals = ln.values
                    if vals and #vals > 1 then
                        for i = 2, #vals do
                            local p0 = vals[i - 1]
                            local p1 = vals[i]
                            vi = _pushLineSegment(verts, vi, p0.x, p0.y, p1.x, p1.y, lw, cr, cg, cb, ca)
                        end
                    end
                else
                    -- Single-segment Line.
                    local x1, y1 = ln.x1, ln.y1
                    local x2, y2 = ln.x2, ln.y2
                    if x1 and y1 and x2 and y2 then
                        vi = _pushLineSegment(verts, vi, x1, y1, x2, y2, lw, cr, cg, cb, ca)
                    end
                end
            end
        end
    end

    for i = #verts, vi + 1, -1 do verts[i] = nil end
    self.vertexCount = vi

    if vi == 0 then
        self.obj:setDrawRange()
        _profEnd(__pf)
        return
    end

    if vi > self.capacity then
        local newCap = self.capacity
        while newCap < vi do newCap = newCap * 2 end
        self.capacity = newCap
        self.obj:release()
        self.obj = _newTriBackingMesh(newCap)
    end

    self.obj:setVertices(verts)
    self.obj:setDrawRange(1, vi)
    _profEnd(__pf)
end

function CollectLinesMesh:draw()
    if not self.Visible then return end
    if self.vertexCount <= 0 then return end
    Render.RenderObject(self)
end

-- =============================================================================
-- CollectEllipsesMesh
-- -----------------------------------------------------------------------------
-- Same idea as CollectCirclesMesh but with independent rx / ry radii. Only
-- fill-mode ellipses are batched; line-mode ellipses stay on the immediate
-- path.
-- =============================================================================
_G.CollectEllipsesMesh = {}
CollectEllipsesMesh.__index = CollectEllipsesMesh
CollectEllipsesMesh.DefaultSeg = 24
CollectEllipsesMesh.InitialCapacity = 256 * 3

function CollectEllipsesMesh.new(initialCapacity)
    local self = setmetatable({}, CollectEllipsesMesh)
    self.capacity = math.max(3, initialCapacity or CollectEllipsesMesh.InitialCapacity)
    self.vertexCount = 0
    self.vertices = {}
    self.obj = _newTriBackingMesh(self.capacity)
    self.obj:setDrawRange()
    self.transform = Matrix.new()
    self.renderid = Render.MeshId
    self.Visible = true
    return self
end

function CollectEllipsesMesh:SetEllipses(ellipses)
    local __pf = _profBegin("Mesh.SetEllipses")
    local verts = self.vertices
    local vi = 0

    if ellipses and #ellipses > 0 then
        for ei = 1, #ellipses do
            local e = ellipses[ei]
            if e and e.Visible ~= false and e.rx and e.ry and e.rx > 0 and e.ry > 0 then
                local cx, cy = e.x or 0, e.y or 0
                local rx, ry = e.rx, e.ry
                local seg = e.seg or CollectEllipsesMesh.DefaultSeg
                if seg < 3 then seg = 3 end

                local col = e.color
                local cr, cg, cb, ca
                if col then
                    cr, cg, cb, ca = col._r or 1, col._g or 1, col._b or 1, col._a or 1
                else
                    cr, cg, cb, ca = 1, 1, 1, 1
                end

                local step = (2 * math.pi) / seg
                local px = cx + rx * math.cos(0)
                local py = cy + ry * math.sin(0)

                for i = 1, seg do
                    local a1 = i * step
                    local nx = cx + rx * math.cos(a1)
                    local ny = cy + ry * math.sin(a1)

                    vi = vi + 1; _writeVertex(verts, vi, cx, cy, 0.5, 0.5, cr, cg, cb, ca)
                    vi = vi + 1; _writeVertex(verts, vi, px, py,
                        (px - cx) / (2 * rx) + 0.5,
                        (py - cy) / (2 * ry) + 0.5,
                        cr, cg, cb, ca)
                    vi = vi + 1; _writeVertex(verts, vi, nx, ny,
                        (nx - cx) / (2 * rx) + 0.5,
                        (ny - cy) / (2 * ry) + 0.5,
                        cr, cg, cb, ca)

                    px, py = nx, ny
                end
            end
        end
    end

    for i = #verts, vi + 1, -1 do verts[i] = nil end
    self.vertexCount = vi

    if vi == 0 then
        self.obj:setDrawRange()
        _profEnd(__pf)
        return
    end

    if vi > self.capacity then
        local newCap = self.capacity
        while newCap < vi do newCap = newCap * 2 end
        self.capacity = newCap
        self.obj:release()
        self.obj = _newTriBackingMesh(newCap)
    end

    self.obj:setVertices(verts)
    self.obj:setDrawRange(1, vi)
    _profEnd(__pf)
end

function CollectEllipsesMesh:draw()
    if not self.Visible then return end
    if self.vertexCount <= 0 then return end
    Render.RenderObject(self)
end

-- =============================================================================
-- CollectPolygonsMesh
-- -----------------------------------------------------------------------------
-- Batches "simple" Polygon objects (Render.PolygonId) into a triangle mesh.
-- Only polygons that satisfy every condition below are accepted; any other
-- polygon must fall back to the immediate Render.RenderObject path, because
-- Polygon has many optional structures (SVG paths, nested circles/rects,
-- stroke paint, non-convex triangulations with per-triangle state, custom
-- transforms ...) that cannot be collapsed to a plain vertex list safely.
--
-- Acceptance rule (Polygon:IsBatchable):
--   * vertices present, length >= 6 (3+ points), even
--   * fill_paint set, no stroke_paint
--   * no svgpaths usage
--   * no child circles / rects / triangles (non-convex path)
--   * no custom transform that differs from identity (keep it simple)
--   * isConvex true or nil (convex-only, use fan triangulation)
-- =============================================================================
_G.CollectPolygonsMesh = {}
CollectPolygonsMesh.__index = CollectPolygonsMesh
CollectPolygonsMesh.InitialCapacity = 256 * 3

function CollectPolygonsMesh.new(initialCapacity)
    local self = setmetatable({}, CollectPolygonsMesh)
    self.capacity = math.max(3, initialCapacity or CollectPolygonsMesh.InitialCapacity)
    self.vertexCount = 0
    self.vertices = {}
    self.obj = _newTriBackingMesh(self.capacity)
    self.obj:setDrawRange()
    self.transform = Matrix.new()
    self.renderid = Render.MeshId
    self.Visible = true
    return self
end

-- Returns true when the given Polygon object is safe to collect. Lives on the
-- collector module (not on Polygon) so Polygon code does not gain any
-- additional dependency.
function CollectPolygonsMesh.IsBatchable(p)
    if not p then return false end
    if p.usesvgpaths then return false end
    if p.stroke_paint then return false end
    if not p.fill_paint then return false end
    if p.circles and #p.circles > 0 then return false end
    if p.rects and #p.rects > 0 then return false end
    if p.triangles and #p.triangles > 0 then return false end
    if not p.vertices or #p.vertices < 6 or (#p.vertices % 2) ~= 0 then return false end
    if p.isConvex == false then return false end
    -- Skip polygons that carry a non-trivial transform; they rely on
    -- RenderSet/Matrix stack semantics inside Render.RenderObject.
    if p.transform and p.transform.IsIdentity and not p.transform:IsIdentity() then
        return false
    end
    return true
end

function CollectPolygonsMesh:SetPolygons(polygons)
    local __pf = _profBegin("Mesh.SetPolygons")
    local verts = self.vertices
    local vi = 0

    if polygons and #polygons > 0 then
        for pi = 1, #polygons do
            local p = polygons[pi]
            if CollectPolygonsMesh.IsBatchable(p) then
                local paint = p.fill_paint
                local cr = paint.r or 1
                local cg = paint.g or 1
                local cb = paint.b or 1
                local ca = paint.a or 1
                -- If fill_paint follows 0..255 (SVG convention), normalize.
                if cr > 1 or cg > 1 or cb > 1 or ca > 1 then
                    cr = cr / 255; cg = cg / 255; cb = cb / 255; ca = ca / 255
                end

                local v = p.vertices
                local x0, y0 = v[1], v[2]
                -- Fan triangulation: (v0, v[i], v[i+1]) for i = 1..n-1
                local count = #v / 2
                for i = 2, count - 1 do
                    local x1, y1 = v[i * 2 - 1], v[i * 2]
                    local x2, y2 = v[i * 2 + 1], v[i * 2 + 2]

                    vi = vi + 1; _writeVertex(verts, vi, x0, y0, 0, 0, cr, cg, cb, ca)
                    vi = vi + 1; _writeVertex(verts, vi, x1, y1, 0, 0, cr, cg, cb, ca)
                    vi = vi + 1; _writeVertex(verts, vi, x2, y2, 0, 0, cr, cg, cb, ca)
                end
            end
        end
    end

    for i = #verts, vi + 1, -1 do verts[i] = nil end
    self.vertexCount = vi

    if vi == 0 then
        self.obj:setDrawRange()
        _profEnd(__pf)
        return
    end

    if vi > self.capacity then
        local newCap = self.capacity
        while newCap < vi do newCap = newCap * 2 end
        self.capacity = newCap
        self.obj:release()
        self.obj = _newTriBackingMesh(newCap)
    end

    self.obj:setVertices(verts)
    self.obj:setDrawRange(1, vi)
    _profEnd(__pf)
end

function CollectPolygonsMesh:draw()
    if not self.Visible then return end
    if self.vertexCount <= 0 then return end
    Render.RenderObject(self)
end

-- =============================================================================
-- CollectCanvasMesh
-- -----------------------------------------------------------------------------
-- Batches many "textured quad" draw calls that share the SAME underlying LOVE
-- Canvas (or Image) into a single dynamic triangle mesh and dispatches them
-- with one draw call per unique texture. This is intended for workloads where
-- hundreds of live entities blit the exact same pre-baked canvas every frame
-- at different positions / rotations (the canonical example is insect monster
-- MonsterAnimCache: every ant instance blits the same ant-frame canvas; every
-- bee instance blits the same bee-frame canvas; etc.). Without batching, each
-- instance issues its own love.graphics.draw(), which hits the CPU-side draw
-- call cost N times per frame. With batching, instances that share a
-- texture collapse into one draw.
--
-- Each "canvas item" is a table of the shape:
--   { tex = <love.graphics.Texture>,  -- required (Image or Canvas userdata)
--     x, y, angle,                    -- world transform (angle in radians)
--     sx, sy,                         -- scale (defaults 1, 1)
--     ox, oy,                         -- origin / anchor in texture pixels
--                                     --    (defaults 0, 0)
--     w, h,                           -- source rect size in pixels
--                                     --    (defaults tex:getWidth/Height)
--     r, g, b, a }                    -- vertex colour multiplier
--
-- The vertex buffer is rebuilt every frame via SetCanvases(items); quads that
-- share `tex` are contiguous in the buffer and drawn with a single
-- setTexture + draw call. Items are expected to be sorted (or grouped) by
-- `tex` on the caller side for maximum batching; SetCanvases groups them
-- internally so an unsorted input still renders correctly (just with one
-- draw per texture change).
-- =============================================================================
_G.CollectCanvasMesh = {}
CollectCanvasMesh.__index = CollectCanvasMesh
-- 6 vertices per quad (two triangles). 256 quads initial capacity.
CollectCanvasMesh.InitialCapacity = 256 * 6

function CollectCanvasMesh.new(initialCapacity)
    local self = setmetatable({}, CollectCanvasMesh)
    self.capacity = math.max(6, initialCapacity or CollectCanvasMesh.InitialCapacity)
    self.vertexCount = 0
    self.vertices = {}
    self.obj = _newTriBackingMesh(self.capacity)
    self.obj:setDrawRange()
    self.transform = Matrix.new()
    self.renderid = Render.MeshId
    self.Visible = true
    -- Per-texture draw ranges: ordered list of { tex, firstVertex, count }
    -- describing one sub-draw per unique texture so the flush can issue
    -- one setTexture + setDrawRange + draw per group.
    self.groups = {}
    return self
end

-- Group `items` by texture in place. Uses a simple linear bucket built from
-- the identity map of textures seen; preserves original order within each
-- bucket so draw order within one texture is stable.
local function _groupByTexture(items)
    local nItems = #items
    if nItems == 0 then return {} end

    -- Fast path: if items already come grouped by texture (the caller did
    -- the sort), we can avoid rebuilding the bucket table.
    local lastTex = items[1].tex
    local grouped = true
    for i = 2, nItems do
        local t = items[i].tex
        if t ~= lastTex then
            -- New texture boundary seen; start a search for an earlier
            -- occurrence of `t`. If there is one, items are not grouped.
            for j = 1, i - 2 do
                if items[j].tex == t then
                    grouped = false
                    break
                end
            end
            if not grouped then break end
            lastTex = t
        end
    end

    if grouped then
        return items
    end

    -- Slow path: rebuild into a grouped array using a texture-indexed bucket.
    local buckets = {}
    local texOrder = {}
    for i = 1, nItems do
        local it = items[i]
        local bucket = buckets[it.tex]
        if not bucket then
            bucket = {}
            buckets[it.tex] = bucket
            texOrder[#texOrder + 1] = it.tex
        end
        bucket[#bucket + 1] = it
    end
    local out = {}
    local oi = 0
    for ti = 1, #texOrder do
        local bucket = buckets[texOrder[ti]]
        for bi = 1, #bucket do
            oi = oi + 1
            out[oi] = bucket[bi]
        end
    end
    return out
end

-- Writes the 6 vertices for a quad at (x, y) with rotation `angle`, scale
-- (sx, sy), origin (ox, oy), size (w, h) and per-vertex colour (cr, cg, cb,
-- ca). UVs go from (0, 0) to (1, 1) across the quad.
local function _pushCanvasQuad(verts, vi, x, y, angle, sx, sy, ox, oy, w, h,
                                cr, cg, cb, ca)
    -- Local-space corners before rotation / scale.
    local lx1, ly1 = -ox, -oy
    local lx2, ly2 = -ox + w, -oy
    local lx3, ly3 = -ox + w, -oy + h
    local lx4, ly4 = -ox, -oy + h

    -- Scale first, then rotate, then translate. Matches the semantics of
    -- love.graphics.draw(tex, x, y, angle, sx, sy, ox, oy).
    lx1, ly1 = lx1 * sx, ly1 * sy
    lx2, ly2 = lx2 * sx, ly2 * sy
    lx3, ly3 = lx3 * sx, ly3 * sy
    lx4, ly4 = lx4 * sx, ly4 * sy

    local cosA, sinA
    if angle and angle ~= 0 then
        cosA = math.cos(angle)
        sinA = math.sin(angle)
    else
        cosA, sinA = 1, 0
    end

    local x1 = x + lx1 * cosA - ly1 * sinA
    local y1 = y + lx1 * sinA + ly1 * cosA
    local x2 = x + lx2 * cosA - ly2 * sinA
    local y2 = y + lx2 * sinA + ly2 * cosA
    local x3 = x + lx3 * cosA - ly3 * sinA
    local y3 = y + lx3 * sinA + ly3 * cosA
    local x4 = x + lx4 * cosA - ly4 * sinA
    local y4 = y + lx4 * sinA + ly4 * cosA

    -- Triangle 1: TL, TR, BR
    vi = vi + 1; _writeVertex(verts, vi, x1, y1, 0, 0, cr, cg, cb, ca)
    vi = vi + 1; _writeVertex(verts, vi, x2, y2, 1, 0, cr, cg, cb, ca)
    vi = vi + 1; _writeVertex(verts, vi, x3, y3, 1, 1, cr, cg, cb, ca)
    -- Triangle 2: TL, BR, BL
    vi = vi + 1; _writeVertex(verts, vi, x1, y1, 0, 0, cr, cg, cb, ca)
    vi = vi + 1; _writeVertex(verts, vi, x3, y3, 1, 1, cr, cg, cb, ca)
    vi = vi + 1; _writeVertex(verts, vi, x4, y4, 0, 1, cr, cg, cb, ca)
    return vi
end

function CollectCanvasMesh:SetCanvases(items)
    local __pf = _profBegin("Mesh.SetCanvases")
    local verts = self.vertices
    local vi = 0
    local groups = self.groups
    -- Reset group list without reallocating.
    for i = #groups, 1, -1 do groups[i] = nil end

    if items and #items > 0 then
        local grouped = _groupByTexture(items)
        local currentTex = nil
        local groupFirst = 0
        for ii = 1, #grouped do
            local it = grouped[ii]
            local tex = it.tex
            if not tex then
                -- Item without texture - skip.
            else
                -- Resolve size defaults from the texture itself.
                local w = it.w
                local h = it.h
                if not w or not h then
                    local ok, tw, th = pcall(function()
                        return tex:getWidth(), tex:getHeight()
                    end)
                    if not ok then tw, th = 64, 64 end
                    w = w or tw
                    h = h or th
                end

                local sx = it.sx or 1
                local sy = it.sy or 1
                local ox = it.ox or 0
                local oy = it.oy or 0
                local angle = it.angle or 0
                local cr = it.r or 1
                local cg = it.g or 1
                local cb = it.b or 1
                local ca = it.a or 1

                -- Group boundary: close previous group, start a new one.
                if tex ~= currentTex then
                    if currentTex ~= nil and vi > groupFirst then
                        groups[#groups + 1] = {
                            tex = currentTex,
                            first = groupFirst + 1,
                            count = vi - groupFirst,
                        }
                    end
                    currentTex = tex
                    groupFirst = vi
                end

                vi = _pushCanvasQuad(verts, vi,
                    it.x or 0, it.y or 0, angle, sx, sy, ox, oy, w, h,
                    cr, cg, cb, ca)
            end
        end
        -- Close the final group.
        if currentTex ~= nil and vi > groupFirst then
            groups[#groups + 1] = {
                tex = currentTex,
                first = groupFirst + 1,
                count = vi - groupFirst,
            }
        end
    end

    for i = #verts, vi + 1, -1 do verts[i] = nil end
    self.vertexCount = vi

    if vi == 0 then
        self.obj:setDrawRange()
        _profEnd(__pf)
        return
    end

    if vi > self.capacity then
        local newCap = self.capacity
        while newCap < vi do newCap = newCap * 2 end
        self.capacity = newCap
        self.obj:release()
        self.obj = _newTriBackingMesh(newCap)
    end

    self.obj:setVertices(verts)
    _profEnd(__pf)
end

-- Unlike the other collectors, CollectCanvasMesh emits one sub-draw per
-- unique texture, so we cannot simply go through Render.RenderObject with
-- a single setDrawRange. Perform the flush ourselves - still a single
-- setVertices upload and one setTexture+draw per texture group.
function CollectCanvasMesh:draw()
    if not self.Visible then return end
    if self.vertexCount <= 0 then return end
    local groups = self.groups
    if #groups == 0 then return end

    -- Preserve caller blend state but force straight alpha so vertex
    -- colour multiplies the texture sample directly.
    local prevR, prevG, prevB, prevA = love.graphics.getColor()
    local prevBlend, prevAlphaMode = love.graphics.getBlendMode()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha", "alphamultiply")

    local m = self.obj
    for gi = 1, #groups do
        local g = groups[gi]
        m:setTexture(g.tex)
        m:setDrawRange(g.first, g.count)
        love.graphics.draw(m)
    end
    m:setDrawRange()
    m:setTexture()

    love.graphics.setColor(prevR, prevG, prevB, prevA)
    love.graphics.setBlendMode(prevBlend, prevAlphaMode)
end

function CollectCanvasMesh:getVertexCount()
    return self.vertexCount
end