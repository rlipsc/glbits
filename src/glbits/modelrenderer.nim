## This module implements a simple, ready to use 3D model renderer.
## Note: Make sure to set the instance colour, as the default colour is black.

import glbits, glbits/[uniforms, utils]

export glbits

type
  ModelId* = distinct int

  ModelInstanceDetails* = tuple[position: GLvectorf3, scale: GLvectorf3, angle: GLfloat, col: GLvectorf4]

  ModelStorage = object
    programId: ShaderProgramId
    vao: VertexArrayObject
    transform: Uniform

const
  VertexBufferIndex* = 0
  VertexColBufferIndex* = 1
  PositionBufferIndex* = 2
  ScaleBufferIndex* = 3
  RotationBufferIndex* = 4
  ColBufferIndex* = 5

var models: seq[ModelStorage]

const
  vertexGLSL = 
    """
    #version 330

    layout(location = 0) in vec3 model;
    layout(location = 1) in vec4 vertexCol;
    layout(location = 2) in vec3 position;
    layout(location = 3) in vec3 scale;
    layout(location = 4) in float angle;
    layout(location = 5) in vec4 colour;

    uniform mat4 transform;

    out vec4 col;

    void main()
    {
      float c = cos(angle);
      float s = sin(angle);

      mat2 rotation = mat2(c, s, -s, c);
      vec3 rotated = vec3(rotation * model.xy, model.z);
      vec4 vertex = vec4(rotated * scale + position, 1.0f);

      gl_Position = transform * vertex;
      col = vertexCol * colour;
    }
    """
  
  fragmentGLSL =
    """
    #version 330

    in vec4 col;
    layout (location = 0) out vec4 colour;

    void main()
    {
        colour = col;
    }
    """

# Short cut access to the per-instance VBOs.

template positionVBO*(modelId: ModelId): untyped = models[modelId.int].vao.buffers[PositionBufferIndex]
template scaleVBO*(modelId: ModelId): untyped = models[modelId.int].vao.buffers[ScaleBufferIndex]
template rotationVBO*(modelId: ModelId): untyped = models[modelId.int].vao.buffers[RotationBufferIndex]
template colVBO*(modelId: ModelId): untyped = models[modelId.int].vao.buffers[ColBufferIndex]

# Type safe access to the underlying VBO data.

template positionVBOArray*(modelId: ModelId): untyped = modelId.positionVBO.toArray(3)
template scaleVBOArray*(modelId: ModelId): untyped = modelId.scaleVBO.toArray(3)
template rotationVBOArray*(modelId: ModelId): untyped = modelId.rotationVBO.toArray(1)
template colVBOArray*(modelId: ModelId): untyped = modelId.colVBO.toArray(4)

proc modelCount*: int = models.len

template modelByIndex*(index: int): ModelId = index.ModelId

template vao*(modelId: ModelId): VertexArrayObject = models[modelId.int].vao

iterator allModels*: ModelId =
  for i in 0 ..< models.len: yield i.ModelId

proc newModelRenderer*: ShaderProgramId = newShaderProgramId(vertexGLSL, fragmentGLSL)

proc programId*(modelId: ModelId): ShaderProgramId =
  models[modelId.int].programId

proc setTransform*(modelId: ModelId, matrix: GLmatrixf4) =
  ## Set the transformation matrix applied to vertices for this model.
  var m = matrix
  modelId.programId.activate
  models[modelId.int].transform.setMat4 m

proc setTransform*(matrix: GLmatrixf4) =
  ## Set the transformation matrix applied to vertices for all models.
  var m = matrix
  for modelId in 0 ..< models.len:
    models[modelId.int].programId.activate
    models[modelId.int].transform.setMat4 m

proc newModel*(shaderProgramId: ShaderProgramId, vertices: openarray[GLvectorf3], colours: openarray[GLvectorf4], aspectRatio = 1.0): ModelId =
  ## Create a new model attached to a shader program.
  models.add ModelStorage(
    programId: shaderProgramId,
    transform: shaderProgramId.getUniformLocation("transform", true),
  )

  result = models.high.ModelId
  template vao: VertexArrayObject = models[result.int].vao
  vao.initVAO()

  var
    model =     initVBO(VertexBufferIndex.GLuint, vertices)
    vertCols =  initVBO(VertexColBufferIndex.GLuint, colours)
    positions = initVBO(PositionBufferIndex.GLuint, 0, fcThree)
    scales =    initVBO(ScaleBufferIndex.GLuint, 0, fcThree)
    rotations = initVBO(RotationBufferIndex.GLuint, 0, fcOne)
    colours =   initVBO(ColBufferIndex.GLuint, 0, fcFour)

  positions.divisor = bdPerInstance
  scales.divisor = bdPerInstance
  rotations.divisor = bdPerInstance
  colours.divisor = bdPerInstance

  vao.add model
  vao.add vertCols
  vao.add positions
  vao.add scales
  vao.add rotations
  vao.add colours

  result.setTransform mat4(1.0)

proc setMaxInstanceCount*(modelId: ModelId, count: int) =
  ## Does not set current instance counts.
  modelId.positionVBO.allocate(count, fcThree)
  modelId.scaleVBO.allocate(count, fcThree)
  modelId.rotationVBO.allocate(count, fcOne)
  modelId.colVBO.allocate(count, fcFour)

template maxInstanceCount*(modelId: ModelId): int =
  models[modelId.int].vao.buffers[PositionBufferIndex].dataLen

proc updateInstance*(modelId: ModelId, index: int, item: ModelInstanceDetails) =
  assert index in 0 ..< modelId.positionVBO.dataLen
  modelId.positionVBOArray[index] = item.position
  modelId.scaleVBOArray[index] = item.scale
  modelId.rotationVBOArray[index] = [item.angle]
  modelId.colVBOArray[index] = item.col

template bindModel(modelId: ModelId) =
  template model: untyped = models[modelId.int]
  programs[model.programId.int].activate
  model.vao.bindArray

proc renderModelCore(modelId: ModelId, count: Natural) =
  ## Render all models/programs.
  template model: untyped = models[modelId.int]
  assert count in 0 .. model.vao.buffers[PositionBufferIndex].dataLen
  model.vao.buffers[VertexBufferIndex].updateGPU()
  model.vao.buffers[VertexColBufferIndex].updateGPU()

  model.vao.buffers[PositionBufferIndex].updateGPU(count)
  model.vao.buffers[ScaleBufferIndex].updateGPU(count)
  model.vao.buffers[RotationBufferIndex].updateGPU(count)
  model.vao.buffers[ColBufferIndex].updateGPU(count)

  model.vao.buffers[VertexBufferIndex].render(count)

template renderModelSetup*(modelId: ModelId, count: Natural, setup: untyped) =
  mixin bindModel
  modelId.bindModel
  template model: auto = modelId
  setup
  renderModelCore(modelId, count)

proc renderModel*(modelId: ModelId, count: Natural) =
  ## Render a particular model.
  modelId.bindModel
  renderModelCore(modelId, count)

proc renderModels* =
  ## Render all models/programs.
  for modelIndex in 0 ..< models.len:
    let maxSize = models[modelIndex].vao.buffers[PositionBufferIndex].dataLen
    modelIndex.ModelId.renderModel(maxSize)

import random
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

    let r1 = points[i]
    model[vertex] = vec3(r1 * cos(curAngle), r1 * sin(curAngle), 0.0)
    colours[vertex] = outsideCol

    model[vertex + 1] = vec3(0.0, 0.0, 0.0)
    colours[vertex + 1] = insideCol

    curAngle += angleInc
    
    let r2 = points[(i + 1) mod triangles]
    model[vertex + 2] = vec3(r2 * cos(curAngle), r2 * sin(curAngle), 0.0)
    colours[vertex + 2] = outsideCol
    vertex += 3

  let r = newModel(shaderProgram, model, colours)
  if maxInstances > 0:
    r.setMaxInstanceCount(maxInstances)
  r

type
  Coordinate2d = concept c
    c.x is SomeFloat
    c.y is SomeFloat

proc makePolyModel*[T: Coordinate2d](shaderProgram: ShaderProgramId, verts: openarray[T], cols: openarray[GLvectorf4], maxInstances = 0): ModelId =
  ## Create a polygon model.
  assert verts.len == cols.len,
    "makePolyModel: 'verts' (length " & $verts.len & ") and 'cols' (length " & $cols.len &
    ") must be of the same length to create a model"
  assert verts.len > 0, "makePolyModel: no vertices supplied"

  when T isnot GLvectorf3:
    var model = newSeq[GLvectorf3](verts.len)
    for i, vert in verts:
      when compiles(vert.z):
        model[i] = vec3(vert.x, vert.y, vert.z)
      else:
        model[i] = vec3(vert.x, vert.y, 0.0)

    result = newModel(shaderProgram, model, cols)
  else:
    # Data is already in the right format.
    result = newModel(shaderProgram, verts, cols)

  if maxInstances > 0:
    result.setMaxInstanceCount(maxInstances)


proc makeRectangleModel*(shaderProgram: ShaderProgramId, col: GLvectorf4, w, h = 2.0, z = 0.0, maxInstances = 0): ModelId =
  ## Create a coloured rectangle model.
  let
    hw = w * 0.5
    hh = h * 0.5
    rectVerts = @[
      vec3(-hw,  hh, z),
      vec3(-hw, -hh, z),
      vec3( hw, -hh, z),

      vec3(-hw,  hh, z),
      vec3( hw, -hh, z),
      vec3( hw,  hh, z),
      ]

  var rectCols = newSeq[GLvectorf4](rectVerts.len)
  for i in 0 ..< rectVerts.len:
    rectCols[i] = col

  result = newModel(shaderProgram, rectVerts, rectCols)
  if maxInstances > 0:
    result.setMaxInstanceCount(maxInstances)

