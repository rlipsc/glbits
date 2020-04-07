import opengl
export opengl

type
  VertexBufferData*[N: static[int]] = ptr UncheckedArray[array[N, GLfloat]]
  BufferType* = enum btPerVertex, btPerInstance
  GLFloatCount* = enum fcOne, fcTwo, fcThree, fcFour

  Vertex3d* = array[3, GLFloat]
  Model3d* = seq[Vertex3d]
  ColModel3d* = seq[(Vertex3d, array[4, GLFloat])]

  VertexBufferObject* = object
    ## Use the id to bind to the VBO.
    id*: GLuint
    ## Whether this buffer processes by vertex or instance.
    bufferType*: BufferType
    ## Pointer to the buffer's data. Use `asArray` to access.
    rawData*: pointer
    ## Size of each `unit of data` as the number of GLfloats.
    dataUnitSize*: GLFloatCount
    ## The maximum number of 'units of data'.
    dataLen*: Natural
    ## Index into parent VAO `buffers`.
    index*: GLuint
    initialised*: bool  
    resize: bool

  VertexArrayObject* = object
    id*: GLuint
    buffers*: seq[VertexBufferObject]

  Shader* = object
    id*: GLuint
    glsl*: string

  ShaderProgram* = object
    id*: GLuint
    linkedShaders*: seq[Shader]
    attachments*: seq[GLenum]

template vec2*(x, y: float|float32): GLvectorf2 = [x.GLfloat, y]
template vec3*(x, y, z: float|float32): GLvectorf3 = [x.GLfloat, y, z]
template vec4*(r, g, b, a: float|float32): GLvectorf4 = [r.GLfloat, g, b, a]

template vec2*(v: float|float32): GLvectorf2 = [v.GLfloat, v]
template vec3*(v: float|float32): GLvectorf3 = [v.GLfloat, v, v]
template vec4*(v: float|float32): GLvectorf4 = [v.GLfloat, v, v, v]

#############
# VBO Support
#############

proc bindBuffer*(buffer: VertexBufferObject) =
  ## Use this buffer
  glBindBuffer(GL_ARRAY_BUFFER, buffer.id)

## Return the number of GLfloats that the dataUnitSize represents.
template toInt(dataUnitSize: GLFloatCount): Natural = dataUnitSize.ord + 1
## Calculate how mang GLfloats are in the buffer.
template floatCount*(vbo: VertexBufferObject): Natural = vbo.dataLen * vbo.dataUnitSize.toInt

proc byteCount*(vbo: VertexBufferObject): Natural =
  ## Calculate the number of bytes this buffer contains.
  vbo.floatCount * sizeOf(GLFloat)

template asArray*(vbo: VertexBufferObject, N: static[int], actions: untyped) =
  ## Access the VBO's `rawData` as an array specified by `dataUnitSize`.
  block:
    let bufferArray {.inject.} = cast[VertexBufferData[N]](vbo.rawData)
    actions

template toArray*(vbo: VertexBufferObject, N: static[int]): auto = cast[VertexBufferData[N]](vbo.rawData)

proc addData*[N: static[int]](vbo: VertexBufferObject, data: openarray[array[N, GLfloat]]) =
  vbo.asArray(N):
    for i in 0 ..< data.len:
      for di, item in data[i]:
        bufferArray[i][di] = item

proc setData*[N: static[int]](vbo: VertexBufferObject, index: Natural, data: array[N, GLfloat]) =
  vbo.asArray:
    bufferArray[index] = item

proc allocate*(vbo: var VertexBufferObject, size: Natural, itemSize: GLFloatCount) =
  ## Allocate memory for data buffer by number of float32s.
  if vbo.rawData != nil: vbo.rawData.dealloc
  vbo.dataUnitSize = itemSize
  vbo.dataLen = size
  vbo.resize = true
  if size > 0: vbo.rawData = alloc0(vbo.byteCount)

proc deallocate*(vbo: var VertexBufferObject) =
  ## Deallocate memory from the buffer.
  if vbo.rawData != nil:
    vbo.rawData = nil
    vbo.rawData.dealloc

proc init*(vbo: var VertexBufferObject, size: Natural, itemSize: GLFloatCount) =
  ## Create a new vertex buffer object.
  vbo.initialised = true
  vbo.allocate(size, itemSize)
  glGenBuffers(1, addr vbo.id)

proc initVBO*(size: Natural, itemSize: GLFloatCount): VertexBufferObject =
  ## Create a new vertex buffer object.
  result.init(size, itemSize)

proc initVBO*[N: static[int]](data: openarray[array[0..N, GLfloat]]): VertexBufferObject =
  ## Create a new vertex buffer object set up from `data`.
  result.init(data.len, GLFloatCount(N))
  result.addData(data)

proc freeVBO*(vbo: var VertexBufferObject, disableVAA = false) =
  if disableVAA: glDisableVertexAttribArray(vbo.index)
  var buffId = vbo.id
  glDeleteBuffers(1, addr buffId)
  vbo.deallocate

proc upload*(vbo: var VertexBufferObject) =
  ## Creates an opengl data store with current data,
  ## use `updateGPU` to update data, which doesn't need to
  ## create a new data store.
  vbo.bindBuffer
  # create open gl data store
  glBufferData(GL_ARRAY_BUFFER, vbo.byteCount, vbo.rawData, GL_STATIC_DRAW)
  # it is safe to deallocate the raw pointer after copying the data to GPU.
  vbo.resize = false

proc updateGPU*(vbo: var VertexBufferObject, itemCount: int) =
  ## Change VBO data on GPU. Faster than creating a new datastore with `upload`,
  ## but assumes the data in `rawData` is present.
  if itemCount == 0: return
  if vbo.resize:
    vbo.upload
  else:
    vbo.bindBuffer
    assert(itemCount <= vbo.dataLen)
    let bytes = GLfloat.sizeOf() * (itemCount * vbo.dataUnitSize.toInt)
    glBufferSubData(GL_ARRAY_BUFFER, 0, bytes, vbo.rawData)

proc updateGPU*(vbo: var VertexBufferObject) =
  ## Send everything in this buffer to the GPU without creating a new datastore.
  if vbo.resize:
    vbo.upload
  else:
    vbo.updateGPU(vbo.dataLen)

proc render*(vbo: VertexBufferObject, instances: int, vertexMode = GL_TRIANGLES) =
  vbo.bindBuffer
  glDrawArraysInstanced(vertexMode, 0.GLint, vbo.floatCount.GLsizei, instances.GLsizei)

#############################
# Vertex array object support
#############################

proc bindArray*(varray: VertexArrayObject) =
  glBindVertexArray(varray.id)

proc initVAO*: VertexArrayObject =
  glGenVertexArrays(1, addr result.id)

proc add*(varray: var VertexArrayObject, vbo: var VertexBufferObject) =
  varray.bindArray
  assert vbo.initialised
  vbo.index = varray.buffers.len.GLuint
  varray.buffers.add(vbo)

  # Set up stride, etc.
  vbo.bindBuffer
  glEnableVertexAttribArray(vbo.index)
  glVertexAttribPointer(vbo.index, vbo.dataUnitSize.toInt.GLint, cGL_FLOAT, GL_FALSE.GLBoolean, 0, nil)
  if vbo.bufferType != btPerVertex:
    glVertexAttribDivisor(vbo.index, 1)

  # Create the opengl data store, this allocates memory on the GPU.
  vbo.upload

################
# Shader support
################

proc logShader*(shaderId: GLuint) =
  var length: GLint = 0
  glGetShaderiv(shaderId, GL_INFO_LOG_LENGTH, length.addr)
  var log: string = newString(length.int)
  glGetShaderInfoLog(shaderId, length, nil, log)
  echo "Shader log: ", log

proc log*(shader: Shader): string =
  var maxLen: GLint
  glGetShaderiv(shader.id, GL_INFO_LOG_LENGTH, maxLen.addr)
  result = newString(maxLen.int)
  glGetShaderInfoLog(shader.id, maxLen, nil, result)

proc newShader*(vertexType: GLenum, source: string): Shader =
  result.glsl = source
  result.id = glCreateShader(vertexType)

  var
    strData: array[1, string] = [source]
    strArr = allocCStringArray(strData)
    compiled: GLint = 0
  try:
    # Zero length indicates zero terminated strings.
    var length: GLint = source.len.GLint
    glShaderSource(result.id, 1, strArr, length.addr)
    glCompileShader(result.id)
    glGetShaderiv(result.id, GL_COMPILE_STATUS, compiled.addr)
    if compiled == 0:
      echo "Compile failed:\n", result.log
      writeStackTrace()
  finally:
    deallocCStringArray(strArr)

proc delete*(shader: Shader) =
  glDeleteShader(shader.id)

#################
# Program support
#################

proc newShaderProgram*: ShaderProgram =
  ## Create a shader program.
  result.id = glCreateProgram()
  result.linkedShaders = @[]

proc delete*(program: ShaderProgram) =
  glDeleteProgram(program.id)

proc activate*(program: ShaderProgram) =
  ## Select this program to use.
  glUseProgram(program.id)

proc log*(program: ShaderProgram): string =
  ## Return any error messages for this program.
  var maxLen: GLint
  glGetProgramiv(program.id, GL_INFO_LOG_LENGTH, addr maxLen);
  # The maxLength includes the NULL character
  result = newString(maxLen.int)
  glGetProgramInfoLog(program.id, maxLen, addr maxLen, result)

proc detach*(program: var ShaderProgram) =
  for shader in program.linkedShaders:
    glDetachShader(program.id, shader.id)
  program.linkedShaders.setLen(0)

proc bindAttribute*(program: ShaderProgram, location: Natural, attribute: string) =
  ## Select this attribute location.
  glBindAttribLocation(program.id, location.GLuint, attribute)

proc attach*(program: var ShaderProgram, shader: Shader) =
  ## Attach a shader to the program.
  for curShader in program.linkedShaders:
    if curShader.id == shader.id:
      return
  glAttachShader(program.id, shader.id)
  program.linkedShaders.add(shader)

proc isLinked*(program: ShaderProgram): bool =
  ## Returns true when the program is successfully linked.
  var isLinked: GLint
  glGetProgramiv(program.id, GL_LINK_STATUS, addr isLinked)
  result = isLinked.bool != GL_FALSE

proc link*(program: ShaderProgram) =
  ## Link shaders in the program together.
  glLinkProgram(program.id)
  if not program.isLinked:
    echo "Error linking: ", program.log

proc isShader*(id: GLuint): bool = glIsShader(id)
proc isProgram*(id: GLuint): bool = glIsProgram(id)

proc setColourAttachments*(values: openarray[GLuint]) =
  ## Can be used outside of program attachments.
  var attachments = @values
  glDrawBuffers(values.len.GLSizei, cast[ptr GLenum](attachments[0].addr))


when isMainModule:
  # This demo assumes SDL2.dll is in the current working directory.
  import sdl2

  discard sdl2.init(INIT_EVERYTHING)

  var
    screenWidth: cint = 640
    screenHeight: cint = 480
    xOffset: cint = 50
    yOffset: cint = 50

  var window = createWindow("SDL/OpenGL Skeleton", xOffset, yOffset, screenWidth, screenHeight, SDL_WINDOW_OPENGL or SDL_WINDOW_RESIZABLE)
  var context = window.glCreateContext()

  # Initialize OpenGL
  loadExtensions()
  glClearColor(0.0, 0.0, 0.0, 1.0)                  # Set background color to black and opaque
  glClearDepth(1.0)                                 # Set background depth to farthest

  var
    model = @[vec3(0.0, 1.0, 0.0), vec3(-1.0, -1.0, 0.0), vec3(1.0, -1.0, 0.0)]
    colours = @[vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 1.0), vec4(0.0, 0.0, 1.0, 1.0)]
    modelVBO = initVBO(model)
    colourVBO = initVBO(colours)
    modelArray = initVAO()
  modelArray.add modelVBO
  modelArray.add colourVBO
  let
    vglsl = 
      """
      #version 330

      layout(location = 0) in vec3 model;
      layout(location = 1) in vec4 vertCol;
      out vec4 col;

      void main()
      {
        gl_Position = vec4(model, 1.0f);
        col = vertCol;
      }
      """
    fglsl =
      """
      #version 330

      in vec4 col;
      layout (location = 0) out vec4 colour;

      void main()
      {
          colour = col;
      }
      """

  let
    vShader = newShader(GL_VERTEX_SHADER, vglsl)
    fShader = newShader(GL_FRAGMENT_SHADER, fglsl)
  var prog = newShaderProgram()
  prog.attach(vShader)
  prog.attach(fShader)
  prog.link
  let progLog = prog.log
  if progLog != "":
    echo "Program error log:\n", progLog

  var
    evt = sdl2.defaultEvent
    running = true

  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  while running:
    while pollEvent(evt):
      if evt.kind == QuitEvent:
        running = false
        break
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
    prog.activate
    modelArray.bindArray
    modelVBO.render(1)
    window.glSwapWindow()
