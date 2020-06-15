#[
  This module implements a simple, ready to use 3D model renderer.
  Note: Make sure to set the instance colour up, as the default colour is black.
]#

import glbits
export glbits

type
  ShaderProgramId* = distinct int
  ModelId* = distinct int
  ModelInstanceDetails* = tuple[position: GLvectorf3, scale: GLvectorf3, angle: GLfloat, col: GLvectorf4]

  ShaderProgramStorage = object
    vShader, fShader: Shader
    program: ShaderProgram

  ModelStorage = object
    programId: ShaderProgramId
    vao: VertexArrayObject

const
  VertexBufferIndex* = 0
  VertexColBufferIndex* = 1
  PositionBufferIndex* = 2
  ScaleBufferIndex* = 3
  RotationBufferIndex* = 4
  ColBufferIndex* = 5

var
  programs: seq[ShaderProgramStorage]
  models: seq[ModelStorage]

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

    out vec4 col;

    void main()
    {
      float c = cos(angle);
      float s = sin(angle);
      mat2 m = mat2(c, s, -s, c);
      vec3 scaledModel = vec3(m * model.xy, model.z) * scale + position;
      gl_Position = vec4(scaledModel, 1.0f);
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

proc newProgram*(vertexGLSL, fragmentGLSL: string): ShaderProgramId =
  ## Create a new shader program.
  var sps: ShaderProgramStorage
  sps.vShader = newShader(GL_VERTEX_SHADER, vertexGLSL)
  sps.fShader = newShader(GL_FRAGMENT_SHADER, fragmentGLSL)
  sps.program = newShaderProgram()
  sps.program.attach sps.vShader
  sps.program.attach sps.fShader
  sps.program.link
  let errorMsg = sps.program.log
  doAssert errorMsg == "", "Error linking shader program:\n" & errorMsg 
  programs.add sps
  result = programs.high.ShaderProgramId

proc newModelRenderer*: ShaderProgramId = newProgram(vertexGLSL, fragmentGLSL)

proc newModel*(shaderProgramId: ShaderProgramId, vertices: openarray[GLvectorf3], colours: openarray[GLvectorf4]): ModelId =
  ## Create a new model attached to a shader program.
  var
    vao = initVAO()
    model = initVBO(vertices)
    vertCols = initVBO(colours)
    positions = initVBO(0, fcThree)
    scales = initVBO(0, fcThree)
    rotations = initVBO(0, fcOne)
    colours = initVBO(0, fcFour)

  positions.bufferType = btPerInstance
  scales.bufferType = btPerInstance
  rotations.bufferType = btPerInstance
  colours.bufferType = btPerInstance

  vao.add model
  vao.add vertCols
  vao.add positions
  vao.add scales
  vao.add rotations
  vao.add colours

  models.add ModelStorage(programId: shaderProgramId, vao: vao)
  result = models.high.ModelId

proc shaderProgram*(shaderProgramId: ShaderProgramId): ShaderProgram = programs[shaderProgramId.int].program

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

proc renderModel*(modelId: ModelId, count: Natural) =
  ## Render all models/programs.
  template model: untyped = models[modelId.int]
  assert count in 0 .. model.vao.buffers[PositionBufferIndex].dataLen
  programs[model.programId.int].program.activate

  model.vao.bindArray
  model.vao.buffers[VertexBufferIndex].updateGPU()
  model.vao.buffers[VertexColBufferIndex].updateGPU()
  #
  model.vao.buffers[PositionBufferIndex].updateGPU(count)
  model.vao.buffers[ScaleBufferIndex].updateGPU(count)
  model.vao.buffers[RotationBufferIndex].updateGPU(count)
  model.vao.buffers[ColBufferIndex].updateGPU(count)

  model.vao.buffers[VertexBufferIndex].render(count)

proc renderModels* =
  ## Render all models/programs.
  for modelIndex in 0 ..< models.len:
    let maxSize = models[modelIndex].vao.buffers[PositionBufferIndex].dataLen
    modelIndex.ModelId.renderModel(maxSize)
