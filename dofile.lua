-- Load math: Vector / Matrix related modules
-- Load render
require('script.render.render')

require('script.debug')
require('script.common.color')
require('script.math.math')
require('script.math.vector')
require('script.3d.math.vector3')
require('script.3d.math.vector4')
require('script.3d.math.matrix3d')
require('script.math.matrix2d')
require('script.math.matrixs')
require('script.math.RotationMatrix')
require('script.math.CovarianceMatrix')
require('script.math.JacobianMatrix2D')

-- Load application
require('script.application')

require('script.polygon.rect')
require('script.polygon.line')
require('script.polygon.circle')
require('script.polygon.polygonevent')

require('script.3d.render.renderset')

-- Load camera
require('script.3d.camera.camera3d')

require('script.render.Pass')

require('script.render.image')
require('script.render.Texture')

-- Load file
require('script.common.filepath')
require('script.file.file')

-- Load uisystem
require('script.uisystem.uisystem')
-- require('script.uisystem.text')
-- require('script.uisystem.button')
-- require('script.uisystem.checkbox')
-- require('script.uisystem.scrollbar')
-- require('script.uisystem.ComboBox')
-- require('script.uisystem.ColorPlane')
-- require('script.uisystem.CurveDataPlane')