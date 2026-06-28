_G.Render = {};

Render.CircleId = 1;
Render.RectId = 2;

Render.PolygonId = 3;

Render.EntityBodyId = 4;

Render.LineId = 5;

Render.CrossLineId = 6;

Render.PowerBarId = 7;

Render.NoiseLineId = 8;

Render.GridDebugViewId = 9;

Render.BoxBoundId = 10;

Render.MeshId = 11;

Render.Box2dId = 12;

Render.CanvasId = 13;

Render.ShaderId = 14

Render.Camera3DId = 15

Render.Mesh3DId = 16

Render.Vector3Id = 17

Render.DirectionLightId = 18

Render.Scene3DId = 19

Render.SceneNode3DId = 20

Render.ImageId = 21

Render.MeshLineId = 22

Render.FrustumId = 23

Render.MeshLinesId = 24

Render.Vector4Id = 25

Render.MatrixId = 26

Render.Matrix3DId = 27

Render.BoundBoxId = 28

Render.LinesId = 29

Render.MeshWaterId = 30

Render.LoveScreenTextId = 31

Render.Tile3DId = 32

Render.PointLightId = 33

Render.ThreeBandSHVectorRGBId = 34

Render.ThreeBandSHVectorId = 35

Render.Triangle2DId = 36

Render.Point3Id = 37

Render.Matrix2DId = 38

Render.Vector2Id = 39

Render.RayId = 40

Render.ImageAnimaId = 41

Render.EdgeId = 42

Render.Ray2DId = 43

Render.UITextId = 44

Render.UIButtonId = 45

Render.UIScrollBarId = 46

Render.UICheckBoxId = 47

Render.UIColorPlaneId = 48

Render.MatrixsId = 49

Render.Point2Id = 50

Render.Point2DCollectId = 51

Render.UIComboBoxId = 52

Render.Triangle3DId = 53

Render.OptionalId = 54

Render.MathFunctionDisplayId = 55

Render.CurvelDataPlaneId = 56

Render.DDAStateFor2DId = 57

Render.DDAStateFor3DId = 58

Render.ImageDataId = 59

Render.Edge3DId = 60

Render.BillBoardId = 61

Render.BillBoardId = 61

Render.FormulaOperatorId = 62
Render.FormulaId = 63

Render.Cone2DId = 64

Render.HistogramId = 65

Render.PathGridId = 67

Render.Polygon2DId = 68

Render.QuaternionID = 69

Render.ComplexID = 70

Render.MeshWaterFFTId = 71

Render.JacobianMatrix2DId = 72

Render.EllipseId = 73

Render.TextureId = 74

Render.getRenderIdName = function(id)
    if type(id) == "table" then
        id = id.renderid
    end
    if Render.CircleId == id then
        return "Circle"
    elseif Render.RectId == id then
        return "Rect"
    elseif Render.PolygonId == id then
        return "Polygon"
    elseif Render.EntityBodyId == id then
        return "EntityBody"
    elseif Render.LineId == id then
        return "Line"
    elseif Render.CrossLineId == id then
        return "CrossLine"
    elseif Render.PowerBarId == id then
        return "PowerBar"
    elseif Render.NoiseLineId == id then
        return "NoiseLine"
    elseif Render.GridDebugViewId == id then
        return "GridDebugView"
    elseif Render.BoxBoundId == id then
        return "Box2D"
    elseif Render.MeshId == id then
        return "Mesh"
    elseif Render.CanvasId == id then
        return "Canvas"
    elseif Render.ShaderId == id then
        return "Shader"
    elseif Render.Vector3Id == id then
        return "Vector3"
    elseif Render.DirectionLightId == id then
        return "DirectionLight"
    elseif Render.Scene3DId == id then
        return "Scene3D"
    elseif Render.SceneNode3DId == id then
        return "SceneNode3D"
    elseif Render.ImageId == id then
        return "image"
    elseif Render.MeshLineId == id then
        return "Line3D"
    elseif Render.FrustumId == id then
        return "Frustum"
    elseif Render.MeshLinesId == id then
        return "MeshLines"
    elseif Render.LinesId == id then
        return "Lines"
    elseif Render.MeshWaterId == id then
        return "MeshWater"
    elseif Render.LoveScreenTextId == id then
        return "LoveScreenText"
    elseif Render.Tile3DId == id then
        return "Tile3DId"
    elseif Render.PointLightId == id then
        return "PointLightId"
    elseif Render.ThreeBandSHVectorRGBId == id then
        return "ThreeBandSHVectorRGBId"
    elseif Render.ThreeBandSHVectorId == id then
        return "ThreeBandSHVectorId"
    elseif Render.Triangle2DId == id then
        return "Triangle2DId"
    elseif Render.Point3Id == id then
        return "Point3Id"
    elseif Render.Matrix2DId == id then
        return "Matrix2DId"
    elseif Render.Vector2Id == id then
        return "Vector2Id"
    elseif Render.RayId == id then
        return "RayId"
    elseif Render.ImageAnimaId == id then
        return "ImageAnimaId"
    elseif Render.EdgeId == id then
        return "EdgeId"
    elseif Render.Ray2DId == id then
        return "Ray2DId"
    elseif  Render.UITextId == id then
        return "UITextId"
    elseif Render.UIComboBoxId == id then
        return "UIComboBox"
    elseif Render.Triangle3DId == id then
        return "Triangle3D"
    elseif Render.OptionalId == id then
        return "Optional"
    elseif Render.MathFunctionDisplayId == id then
        return "MathFunctionDisplay"
    elseif Render.CurvelDataPlaneId == id then
        return "CurvelDataPlane"
    elseif Render.DDAStateFor2DId == id then
        return "DDAStateFor2D"
    elseif Render.DDAStateFor3DId == id then
        return "DDAStateFor3D"
	elseif Render.ImageDataId == id then
        return "ImageDataId"
    elseif Render.Edge3DId == id then
        return "Edge3D"
    elseif Render.BillBoardId == id then
        return "BillBoard"
    elseif Render.Cone2DId == id then
        return "Cone2D"
    elseif Render.HistogramId == id then
        return "Histogram"
    elseif Render.PathGridId == id then
        return "PathGridData"
    elseif Render.Polygon2DId == id then
        return "Polygon2D"
    elseif Render.QuaternionID == id then
        return "Quaternion"
    elseif Render.ComplexID == id then
        return "Complex"
    elseif Render.MeshWaterFFTId == id then
        return "MeshWaterFFT"
    elseif Render.JacobianMatrix2DId == id then
        return "JacobianMatrix2D"
    elseif Render.EllipseId == id then
        return "Ellipse"
    elseif Render.TextureId == id then
        return "Texture"
    end
    
    return "Null"
end

Render.RenderObject = function(obj)
   
end
