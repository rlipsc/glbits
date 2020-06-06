import glbits/modelRenderer, random

from math import TAU, cos, sin

proc makeCircleModel*(shaderProgram: ShaderProgramId, triangles: int, insideCol, outsideCol: GLvectorf4, roughness = 0.0, maxInstances = 0): ModelId =
  ## Create a coloured model with `triangles` sides.
  let angleInc = TAU / triangles.float
  const radius = 1.0
  var
    model = newSeq[GLvectorf3](triangles * 3)
    colours = newSeq[GLvectorf4](triangles * 3)
    curAngle = 0.0
    vertex = 0
    points = newSeq[float](triangles)

  for i in 0 ..< points.len:
    points[i] = radius + rand(roughness)
  
  for i in 0 ..< triangles:

    model[vertex] = vec3(0.0, 0.0, 0.0)
    colours[vertex] = insideCol
    
    let r1 = points[i]
    model[vertex + 1] = vec3(r1 * cos(curAngle), r1 * sin(curAngle), 0.0)
    colours[vertex + 1] = outsideCol
    
    curAngle += angleInc
    
    let r2 = points[(i + 1) mod triangles]
    model[vertex + 2] = vec3(r2 * cos(curAngle), r2 * sin(curAngle), 0.0)
    colours[vertex + 2] = outsideCol
    vertex += 3

  let r = newModel(shaderProgram, model, colours)
  if maxInstances > 0:
    r.setMaxInstanceCount(maxInstances)
  r

