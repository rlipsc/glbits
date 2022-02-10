import opengl, utils, strformat, debugutils, tables
export opengl, tables


type
  VertexBufferData*[N: static[int]] = ptr UncheckedArray[array[N, GLfloat]]
  BufferDivisor* = enum bdPerVertex, bdPerInstance
  BufferTarget* = enum
    btVertexAttributes = GL_ARRAY_BUFFER,
    btVertexArrayIndices = GL_ELEMENT_ARRAY_BUFFER
    btPixelReadTarget = GL_PIXEL_PACK_BUFFER,
    btTextureDataSource = GL_PIXEL_UNPACK_BUFFER,
    btUniformBlockStorage = GL_UNIFORM_BUFFER,
    btTextureDataBuffer = GL_TEXTURE_BUFFER,
    btTransformFeedbackBuffer = GL_TRANSFORM_FEEDBACK_BUFFER,
    btBufferCopySource = GL_COPY_READ_BUFFER,
    btBufferCopyDestination = GL_COPY_WRITE_BUFFER,
    btIndirectCommandArguments = GL_DRAW_INDIRECT_BUFFER,
    btShaderStorage = GL_SHADER_STORAGE_BUFFER,
    btIndirectComputeDispatchCommands = GL_DISPATCH_INDIRECT_BUFFER,
    btQueryResultBuffer = GL_QUERY_BUFFER,
    btAtomicCounterStorage = GL_ATOMIC_COUNTER_BUFFER,

  GLFloatCount* = enum fcOne, fcTwo, fcThree, fcFour

  Vertex3d* = array[3, GLFloat]
  Model3d* = seq[Vertex3d]
  ColModel3d* = seq[(Vertex3d, array[4, GLFloat])]

  VertexBufferObject* = object
    id*: GLuint ## Use the id to bind to the VBO.
    divisor*: BufferDivisor ## Whether this buffer processes by vertex or instance.
    target*: BufferTarget ## What this buffer represents.
    rawData*: pointer ## Pointer to the buffer's data. Use `asArray` to access.
    dataUnitSize*: GLFloatCount ## Size of each `unit of data` as the number of GLfloats.
    dataLen*: Natural ## The maximum number of 'units of data'.
    index*: GLuint    ## Index into parent VAO `buffers`.
    initialised*: bool  
    resize: bool
    changed: bool

  VertexArrayObject* = object
    id*: GLuint
    buffers*: seq[VertexBufferObject]

  Shader* = object
    id*: GLuint
    glsl*: string

  Attribute* = distinct GLint
  Uniform* = distinct GLint

  ## Represents information about an Attribute or Uniform.
  ShaderInputItem*[T: Attribute or Uniform] = object
    name*: string
    id*: T
    glType*: GLenum
    length*: GLsizei
    size*: GLint

  ShaderUniforms* = Table[string, ShaderInputItem[Uniform]]
  ShaderAttributes* = Table[string, ShaderInputItem[Attribute]]

  ShaderProgram* = object
    id*: GLuint
    linkedShaders*: seq[Shader]
    vertexMode*: GLenum
    uniforms*: ShaderUniforms
    attributes*: ShaderAttributes

  ShaderProgramId* = distinct int

  GLLogMessages* = object
    sources*: seq[GLenum]
    types*: seq[GLenum]
    severities*: seq[GLenum]
    ids*: seq[GLuint]
    lengths*: seq[GLsizei]
    messages*: seq[string]

template glBool*(v: bool): GLBoolean = 
  if v == true: GL_TRUE else: GL_FALSE

proc `$`*(bufferTarget: BufferTarget): string =
  assert bufferTarget in BufferTarget.low .. BufferTarget.high, "bufferTarget is invalid: " & $bufferTarget.ord
  case bufferTarget
  of btVertexAttributes: "GL_ARRAY_BUFFER"
  of btVertexArrayIndices: "GL_ELEMENT_ARRAY_BUFFER"
  of btPixelReadTarget: "GL_PIXEL_PACK_BUFFER"
  of btTextureDataSource: "GL_PIXEL_UNPACK_BUFFER"
  of btUniformBlockStorage: "GL_UNIFORM_BUFFER"
  of btTextureDataBuffer: "GL_TEXTURE_BUFFER"
  of btTransformFeedbackBuffer: "GL_TRANSFORM_FEEDBACK_BUFFER"
  of btBufferCopySource: "GL_COPY_READ_BUFFER"
  of btBufferCopyDestination: "GL_COPY_WRITE_BUFFER"
  of btIndirectCommandArguments: "GL_DRAW_INDIRECT_BUFFER"
  of btShaderStorage: "GL_SHADER_STORAGE_BUFFER"
  of btIndirectComputeDispatchCommands: "GL_DISPATCH_INDIRECT_BUFFER"
  of btQueryResultBuffer: "GL_QUERY_BUFFER"
  of btAtomicCounterStorage: "GL_ATOMIC_COUNTER_BUFFER"

#------------
# VBO Support
#------------

proc bindBuffer*(buffer: VertexBufferObject, target: BufferTarget) {.inline.} =
  ## Use this buffer as this target
  glBindBuffer(target.GLenum, buffer.id)
  debugMsg &"Bound [buffer {buffer.id}] as {target}"

proc bindBuffer*(buffer: VertexBufferObject) {.inline.} =
  ## Use this buffer
  glBindBuffer(buffer.target.GLenum, buffer.id)
  debugMsg &"Bound [buffer {buffer.id}] using buffer's default target of {buffer.target}"

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
  debugMsg &"Allocated {size} bytes for [buffer {vbo.id}]"

proc deallocate*(vbo: var VertexBufferObject) =
  ## Deallocate memory from the buffer.
  if vbo.rawData != nil:
    vbo.rawData = nil
    vbo.rawData.dealloc
    debugMsg &"Deallocated [buffer {vbo.id}]"
  else:
    debugMsg &"Asked to deallocate [buffer {vbo.id}] but it is already nil"

proc init*(vbo: var VertexBufferObject, index: GLuint, bufferTarget = btVertexAttributes) =
  vbo.initialised = true
  vbo.changed = true
  vbo.target = bufferTarget
  vbo.index = index
  glGenBuffers(1, addr vbo.id)
  debugMsg &"Created new [buffer {vbo.id}]"

proc init*(vbo: var VertexBufferObject, index: GLuint, size: Natural, itemSize: GLFloatCount, target = btVertexAttributes) =
  ## Create a new vertex buffer object.
  vbo.init(index, target)
  vbo.allocate(size, itemSize)
  debugMsg &"Created new [buffer {vbo.id}]"

proc initVBO*(index: GLuint, size: Natural, itemSize: GLFloatCount): VertexBufferObject =
  ## Create a new vertex buffer object.
  result.init(index, size, itemSize)

proc initVBO*[N: static[int]](index: GLuint, data: openarray[array[0..N, GLfloat]]): VertexBufferObject =
  ## Create a new vertex buffer object set up from `data`.
  result.init(index, data.len, GLFloatCount(N))
  result.addData(data)
  when defined(debugGL):
    const ty = case N
      of 2: "GLVectorf2"
      of 3: "GLVectorf3"
      of 4: "GLVectorf4"
      else:
        "float count " & $N
    debugMsg &"Added {data.len} items of {ty} to [buffer {result.id}]"

proc freeVBO*(vbo: var VertexBufferObject, disableVAA = false) =
  if disableVAA: glDisableVertexAttribArray(vbo.id)
  var buffId = vbo.id
  glDeleteBuffers(1, addr buffId)
  vbo.deallocate
  debugMsg &"Freed [buffer {vbo.id}]"

proc upload*(vbo: var VertexBufferObject) =
  ## Creates an opengl data store with current data,
  ## use `updateGPU` to update data, which doesn't need to
  ## create a new data store.
  vbo.bindBuffer
  # create open gl data store
  glBufferData(vbo.target.GLenum, vbo.byteCount, vbo.rawData, GL_STATIC_DRAW)
  # it is safe to deallocate the raw pointer after copying the data to GPU.
  vbo.resize = false
  debugMsg &"Uploaded {vbo.byteCount} bytes to array [buffer {vbo.id}]"

proc upload*(vbo: var VertexBufferObject, target: BufferTarget) =
  ## Creates an opengl data store with current data,
  ## use `updateGPU` to update data, which doesn't need to
  ## create a new data store.
  vbo.bindBuffer(target)
  # create open gl data store
  glBufferData(target.GLenum, vbo.byteCount, vbo.rawData, GL_STATIC_DRAW)
  # it is safe to deallocate the raw pointer after copying the data to GPU.
  vbo.resize = false
  debugMsg &"Uploaded {vbo.byteCount} bytes to array [buffer {vbo.id}]"

proc updateGPU*(vbo: var VertexBufferObject, itemCount: int) =
  ## Change VBO data on GPU. Faster than creating a new datastore with `upload`,
  ## but assumes the data in `rawData` is present.
  if itemCount == 0: return
  if vbo.resize:
    vbo.upload
  else:
    vbo.bindBuffer
    assert itemCount <= vbo.dataLen, "Exceeded capacity for vbo. Index: " & $vbo.index & ", max: " & $vbo.dataLen & ", item count requested: " & $itemCount
    let bytes = GLfloat.sizeOf() * (itemCount * vbo.dataUnitSize.toInt)
    glBufferSubData(vbo.target.GLenum, 0, bytes, vbo.rawData)
    debugMsg &"Updated {vbo.id} with {bytes} bytes"

proc updateGPU*(vbo: var VertexBufferObject) =
  ## Send everything in this buffer to the GPU without creating a new datastore.
  if vbo.resize:
    vbo.upload
  else:
    vbo.updateGPU(vbo.dataLen)

proc render*(vbo: VertexBufferObject, instances: int, vertexMode = GL_TRIANGLES) =
  ## Draw multiple instances of a range of elements.
  vbo.bindBuffer
  debugMsg &"Drawing models using VBO {vbo.id} with {instances} instances and float count {vbo.floatCount}"
  glDrawArraysInstanced(vertexMode, 0.GLint, vbo.floatCount.GLsizei, instances.GLsizei)

proc `$`*(buffer: VertexBufferObject): string =
  result = &"[ID: {buffer.id.int}, Index: {buffer.index}, Target: {buffer.target}, DataUnitSize = {buffer.dataUnitSize}, "
  result &= &"Item Count: {buffer.dataLen}, Initialised: {buffer.initialised}, Changed: {buffer.changed}, Data:\n"
  case buffer.dataUnitSize
    of fcTwo:
      buffer.asArray(2):
        if buffer.dataLen > 0:
          result &= $bufferArray[0]
          for i in 1..<buffer.dataLen:
            result &= ", " & $bufferArray[i]
    of fcThree:
      buffer.asArray(3):
        if buffer.dataLen > 0:
          result &= $bufferArray[0]
          for i in 1..<buffer.dataLen:
            result &= ", " & $bufferArray[i]
    else:
      # display as floats
      buffer.asArray(1):
        if buffer.dataLen > 0:
          result &= $bufferArray[0]
          for i in 1..<buffer.dataLen:
            result &= ", " & $bufferArray[i]
  result &= "]"


#-------------------
# Attributes support
#-------------------

proc setInfo*(index: Attribute, size, stride, offset: int, glType = cGL_FLOAt, normalised = false) =
  glVertexAttribPointer(index.GLuint, size.GLint, glType, glBool(normalised), stride.GLsizei, cast[pointer](offset))                                   # position
  debugMsg &"Set info: index {index.int} size: {size} stride: {stride} offset: {offset} type: {glType.int} normalised: {normalised}"

proc perInstance*(attribute: Attribute) =
  glVertexAttribDivisor(attribute.GLuint, 1)
  debugMsg &"Set attribute {attribute.int} to per instance"

proc perVertex*(attribute: Attribute) =
  glVertexAttribDivisor(attribute.GLuint, 0)
  debugMsg &"Set attribute {attribute.int} to per vertex"

template enableAttributes*(v: HSlice[system.int, system.int]): untyped =
  for i in v:
    glEnableVertexAttribArray(i.GLuint)

#----------------------------
# Vertex array object support
#----------------------------

proc bindArray*(varray: VertexArrayObject) =
  glBindVertexArray(varray.id)
  debugMsg &"Binding array {varray.id}"

proc initVAO*(vao: var VertexArrayObject) =
  glGenVertexArrays(1, addr vao.id)
  debugMsg &"Create array {vao.id}"

proc initVAO*: VertexArrayObject =
  result.initVao

import strformat

proc add*(varray: var VertexArrayObject, vbo: var VertexBufferObject) =
  varray.bindArray
  assert vbo.initialised
  varray.buffers.add(vbo)

  # Set up stride, etc.
  vbo.bindBuffer
  glEnableVertexAttribArray(vbo.index)
  debugMsg &"Enabled attribute {vbo.index.int}"

  glVertexAttribPointer(vbo.index, vbo.dataUnitSize.toInt.GLint, cGL_FLOAT, GL_FALSE.GLBoolean, 0, nil)
  debugMsg &"Attribute {vbo.index.int} set to index {vbo.index}, data unit size: {vbo.dataUnitSize.toInt}"

  if vbo.divisor != bdPerVertex:
    glVertexAttribDivisor(vbo.index, 1)
    debugMsg &"Set divisor for attribute {vbo.index.int} to {vbo.divisor}"

  # Create the opengl data store, this allocates memory on the GPU.
  vbo.upload

proc initVAO*(setup: openarray[tuple[index: GLuint, maxItems: Natural, floatCount: GLFloatCount, divisor: BufferDivisor]]): VertexArrayObject =
  result = initVAO()
  for item in setup:
    var vbo = initVBO(item.index, item.maxItems, item.floatCount)
    vbo.divisor = item.divisor
    result.add vbo

proc uploadChanges*(vao: var VertexArrayObject, instanceCount: Natural) =
  for i in 0 ..< vao.buffers.len:
    case vao.buffers[i].divisor
      of bdPerVertex:
        if vao.buffers[i].changed:
          vao.buffers[i].updateGPU
          vao.buffers[i].changed = false
      of bdPerInstance:
        # update length of buffer info for shader based on number of entities
        #vao.buffers[i].dataLen = model.renderCount * model.varray.buffers[i].dataSize #info.floatCount * group.entities.len
        vao.buffers[i].updateGPU(instanceCount)

proc `$`*(varray: VertexArrayObject): string =
  result = "Vertex Array Object " & $varray.id & " <\n"
  for i in 0 ..< varray.buffers.len:
    result &= $varray.buffers[i] & "\n"
  result &= ">"

#---------------
# Shader support
#---------------

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

proc newShader*(shader: var Shader, vertexType: GLenum, source: string) =
  shader.glsl = source
  shader.id = glCreateShader(vertexType)

  var
    strData: array[1, string] = [source]
    strArr = allocCStringArray(strData)
    compiled: GLint = 0
  try:
    # Zero length indicates zero terminated strings.
    var length: GLint = source.len.GLint
    glShaderSource(shader.id, 1, strArr, length.addr)
    glCompileShader(shader.id)
    glGetShaderiv(shader.id, GL_COMPILE_STATUS, compiled.addr)
    if compiled == 0:
      echo "Compile failed:\n", shader.log
      writeStackTrace()
  finally:
    deallocCStringArray(strArr)
  debugMsg &"Created new shader {shader.id}"

proc newShader*(vertexType: GLenum, source: string): Shader =
  result.newShader(vertexType, source)

proc delete*(shader: Shader) =
  glDeleteShader(shader.id)
  debugMsg &"Deleting shader {shader.id}"

proc detach*(program: GLuint, shaderId: GLuint) =
  glDetachShader(program, shaderId)
  debugMsg &"Detaching shader {shaderId}"

#----------------
# Program support
#----------------

proc newShaderProgram*(sp: var ShaderProgram, vertexMode = GL_TRIANGLES) =
  ## Create a shader program.
  sp.id = glCreateProgram()
  sp.linkedShaders = @[]
  sp.vertexMode = vertexMode
  debugMsg &"New shader program {sp.id.int}"

proc newShaderProgram*(vertexMode = GL_TRIANGLES): ShaderProgram =
  result.newShaderProgram(vertexMode)

proc attach*(program: var ShaderProgram, shader: Shader) =
  ## Attach a shader to the program.
  for curShader in program.linkedShaders:
    if curShader.id == shader.id:
      return
  glAttachShader(program.id, shader.id)
  program.linkedShaders.add(shader)
  debugMsg &"Attaching shader {shader.id} to program {program.id}"

proc isLinked*(program: ShaderProgram): bool =
  ## Returns true when the program is successfully linked.
  var isLinked: GLint
  glGetProgramiv(program.id, GL_LINK_STATUS, addr isLinked)
  result = isLinked.bool != GL_FALSE

proc log*(program: ShaderProgram): string =
  ## Return any error messages for this program.
  var maxLen: GLint
  glGetProgramiv(program.id, GL_INFO_LOG_LENGTH, addr maxLen);
  # The maxLength includes the NULL character
  result = newString(maxLen.int)
  glGetProgramInfoLog(program.id, maxLen, addr maxLen, result)

proc `$`*(shaderInput: ShaderInputItem): string =
  "(name: " & shaderInput.name & ", id: " & $shaderInput.id.int & ", type: " & shaderInput.glType.glTypeToStr & ", size: " & $shaderInput.size.int & ")"

proc `$`*(shaderInputs: seq[ShaderInputItem]): string =
  for shaderInput in shaderInputs: result &= $shaderInput & "\n"

proc getAttributes*(programId: GLuint): ShaderAttributes =
  ## Return a list of information about the attributes in this program.
  glUseProgram(programId);

  var attribCount: GLint
  glGetProgramiv(programId, GL_ACTIVE_ATTRIBUTES, attribCount.addr)

  var name = newString(64)
  for attrib in 0 ..< attribCount:
    var
      size: GLint
      itemType: GLenum
      length: GLsizei
      buffSize = name.len.GLsizei
    glGetActiveAttrib(programId, attrib.GLuint, buffSize, length.addr, size.addr, itemType.addr, name);

    var loc = glGetAttribLocation(programId, name);
    if loc > -1:
      let n = name[0 ..< length]
      result[n] = ShaderInputItem[Attribute](
        name: n,
        id: loc.Attribute,
        glType: itemType
      )

proc getUniforms*(programId: GLuint): ShaderUniforms =
  ## Return a list of information about the uniforms in this program.
  glUseProgram(programId);

  var uniCount: GLint
  glGetProgramiv(programId, GL_ACTIVE_UNIFORMS, uniCount.addr)

  var name = newString(64)
  for uni in 0 ..< uniCount:
    var
      size: GLint
      itemType: GLenum
      length: GLsizei
      buffSize = name.len.GLsizei
    glGetActiveUniform(programId, uni.GLuint, buffSize, length.addr, size.addr, itemType.addr, name);

    var loc = glGetUniformLocation(programId, name);
    if loc > -1:
      let n = name[0 ..< length]
      result[n] = ShaderInputItem[Uniform](
        name: n,
        id: loc.Uniform,
        glType: itemType
      )

proc link*(program: var ShaderProgram) =
  ## Link shaders in the program together.
  glLinkProgram(program.id)
  doAssert program.isLinked, "Error linking shader program: " & program.log
  debugMsg &"Linked shader program {program.id.int}"

  # Fetch uniforms and attributes.
  program.attributes = program.id.getAttributes()
  program.uniforms = program.id.getUniforms()

proc getCurrentProgram*: GLint =
  glGetIntegerv(GL_CURRENT_PROGRAM, result.addr)

proc name*(program: ShaderProgram, attribute: Attribute): string =
  for a in program.attributes.values:
    if a.id.int == attribute.int:
      return a.name

proc name*(program: ShaderProgram, uniform: Uniform): string =
  for u in program.uniforms.values:
    if u.id.int == uniform.int:
      return u.name

proc newShaderProgram*(program: var ShaderProgram, vertexGLSL, fragmentGLSL: string, vertexMode = GL_TRIANGLES) =
  ## Create a new shader program id.
  program = newShaderProgram(vertexMode)
  # ShaderProgramStorage
  program.attach newShader(GL_VERTEX_SHADER, vertexGLSL)
  program.attach newShader(GL_FRAGMENT_SHADER, fragmentGLSL)
  program.link

proc newShaderProgram*(vertexGLSL, fragmentGLSL: string, vertexMode = GL_TRIANGLES): ShaderProgram =
  result.newShaderProgram(vertexGLSL, fragmentGLSL, vertexMode)

proc detach*(program: var ShaderProgram) =
  for shader in program.linkedShaders:
    program.id.detach shader.id
  program.linkedShaders.setLen(0)

proc delete*(program: var ShaderProgram) =
  program.detach
  glDeleteProgram(program.id)
  debugMsg &"Deleted program {program.id}"

proc activate*(program: ShaderProgram) =
  ## Select this program to use.
  glUseProgram(program.id)
  debugMsg &"Activating program {program.id}"

proc bindAttribute*(program: ShaderProgram, location: Natural, attribute: string) =
  ## Select this attribute location.
  glBindAttribLocation(program.id, location.GLuint, attribute)
  debugMsg &"Binding attribute {location.int} in program {program.id}"

template withProgram*(program: ShaderProgram, actions: untyped): untyped =
  program.activate
  actions

#------------------------------------------------------
# ShaderProgramId, a distinct id representing a program
# This is just an index into an array of ShaderPrograms
# to avoid passing around the shader data.
#------------------------------------------------------

var programs*: seq[ShaderProgram]

proc newShaderProgramId*(vertexGLSL, fragmentGLSL: string, vertexMode = GL_TRIANGLES): ShaderProgramId =
  programs.add newShaderProgram(vertexGLSL, fragmentGLSL, vertexMode)
  result = programs.high.ShaderProgramId

proc newShaderProgramId*(vertexMode = GL_TRIANGLES): ShaderProgramId =
  programs.add newShaderProgram(vertexMode)
  result = programs.high.ShaderProgramId

template program*(id: ShaderProgramId): ShaderProgram = programs[id.int]
proc id*(programId: ShaderProgramId): GLuint = programs[programId.int].id

proc activate*(program: ShaderProgramId) =
  ## Select this program to use.
  programs[program.int].activate

proc attach*(programId: ShaderProgramId, shader: Shader) = programId.program.attach shader
proc link*(programId: ShaderProgramId) = programId.program.link
proc delete*(programId: ShaderProgramId) = programId.program.delete

proc name*(attribute: Attribute): string =
  let curProg = getCurrentProgram()
  for i in 0 ..< programs.len:
    if programs[i].id.GLint == curProg:
      return programs[i].name(attribute)
  $attribute.int

proc name*(uniform: Uniform): string =
  let curProg = getCurrentProgram()
  for i in 0 ..< programs.len:
    if programs[i].id.GLint == curProg:
      return programs[i].name(uniform)
  $uniform.int

template renderWith*(programId: ShaderProgramId, vao: VertexArrayObject, modelBufIdx: Natural, instances: int, frameBuffId: GLuint, setupActions: untyped) =
  if frameBuffId > 0.GLuint:
    debugMsg "Binding [frame buffer " & $frameBuffId & "]"
    glBindFramebuffer(GL_FRAMEBUFFER, frameBuffId)
  glEnableClientState(GL_VERTEX_ARRAY)

  template modelBuf: untyped = vao.buffers[VertexBufferIndex]

  programId.activate
  
  setupActions
  
  vao.bindArray
  modelBuf.bindBuffer

  debugMsg "Drawing " & $instances & " models of " & $modelBuf.dataLen.int & " vertices"
  glDrawArraysInstanced(programId.program.vertexMode, 0, modelBuf.dataLen.GLsizei, instances.GLsizei)

#-----
# Misc
#-----

proc isShader*(id: GLuint): bool = glIsShader(id)
proc isProgram*(id: GLuint): bool = glIsProgram(id)

proc setColourAttachments*(values: var seq[GLuint]) =
  ## Can be used outside of program attachments.
  glDrawBuffers(values.len.GLSizei, cast[ptr GLenum](values[0].addr))
  debugMsg &"Set colour attachments to {values}"

proc getAttributeLocation*(program: ShaderProgram, attrib: string): Attribute = glGetAttribLocation(program.id, attrib).Attribute

proc getLogMessages*(messageCount: Natural): GLLogMessages =
  ## Returns debugging messages when GL_DEBUG is active.
  ## See: https://www.khronos.org/opengl/wiki/Debug_Output
  var maxMsgLen: GLint
  glGetIntegerv(GL_MAX_DEBUG_MESSAGE_LENGTH, maxMsgLen.addr)

  let logSize = messageCount * maxMsgLen
  var msgData = newSeq[GLchar](logSize)

  result.sources.setLen(messageCount)
  result.types.setLen(messageCount)
  result.severities.setLen(messageCount)
  result.ids.setLen(messageCount)
  result.lengths.setLen(messageCount)

  let numFound = glGetDebugMessageLog(
    messageCount.GLuint, logSize.GLsizei,
    result.sources[0].addr,
    result.types[0].addr,
    result.ids[0].addr,
    result.severities[0].addr,
    result.lengths[0].addr,
    msgData[0].addr)

  result.sources.setLen numFound
  result.types.setLen numFound
  result.severities.setLen numFound
  result.ids.setLen numFound
  result.lengths.setLen numFound

  result.messages.setLen numFound

  var curPos = 0
  for i, msgLen in result.lengths:
    result.messages[i] = newString(msgLen - 1)
    let
      source = msgData[curPos].addr
      dest = result.messages[i][0].addr
    copyMem dest, source, msgLen - 1
    curPos += msgLen

proc glTypeToStr*(glType: GLenum): string =
  case glType
  of cGL_FLOAT: "GL_FLOAT"
  of GL_FLOAT_VEC2: "GL_FLOAT_VEC2"
  of GL_FLOAT_VEC3: "GL_FLOAT_VEC3"
  of GL_FLOAT_VEC4: "GL_FLOAT_VEC4"
  of GL_FLOAT_MAT2: "GL_FLOAT_MAT2"
  of GL_FLOAT_MAT3: "GL_FLOAT_MAT3"
  of GL_FLOAT_MAT4: "GL_FLOAT_MAT4"
  of GL_SAMPLER_2D_ARB: "GL_SAMPLER_2D_ARB"
  #[of GL_FLOAT_MAT2x3
  of GL_FLOAT_MAT2x4
  of GL_FLOAT_MAT3x2, GL_FLOAT_MAT3x4, GL_FLOAT_MAT4x2, GL_FLOAT_MAT4x3,
  GL_INT, GL_INT_VEC2, GL_INT_VEC3, GL_INT_VEC4, GL_UNSIGNED_INT, GL_UNSIGNED_INT_VEC2, GL_UNSIGNED_INT_VEC3, GL_UNSIGNED_INT_VEC4, GL_DOUBLE, GL_DOUBLE_VEC2, GL_DOUBLE_VEC3, GL_DOUBLE_VEC4, GL_DOUBLE_MAT2, GL_DOUBLE_MAT3, GL_DOUBLE_MAT4, GL_DOUBLE_MAT2x3, GL_DOUBLE_MAT2x4, GL_DOUBLE_MAT3x2, GL_DOUBLE_MAT3x4, GL_DOUBLE_MAT4x2, or GL_DOUBLE_MAT4x3  ]#
  else:
    "Unknown (" & $glType.int & ")"

proc activateAllAttributes*(programId: GLuint, report = false) =
  ## Enable all attributes used in this program.
  let attributes = programId.getAttributes
  if report:
    echo "Activated attributes for program id " & $programId.int & ":"
  for attr in attributes.values:
    glEnableVertexAttribArray(attr.id.GLuint)
    if report: echo " ", attr

#-----
# Demo
#-----

when isMainModule:
  # This demo assumes SDL2.dll is in the current working directory.
  import sdl2, uniforms, times

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
  glClearColor(0.0, 0.0, 0.0, 1.0)                  # Set background colour to black and opaque
  glClearDepth(1.0)                                 # Set background depth to farthest

  var
    model = @[vec3(0.0, 1.0, 0.0), vec3(-1.0, -1.0, 0.0), vec3(1.0, -1.0, 0.0)]
    colours = @[vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 1.0), vec4(0.0, 0.0, 1.0, 1.0)]
    modelVBO = initVBO(0.GLuint, model)
    colourVBO = initVBO(1.GLuint, colours)
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

      uniform float time;
      uniform vec2 resolution;
      const float PI = 3.141592653589793;
      const float TAU = PI * 2.0;

      const float thingSize = 0.35;
      const float points = 8.0;
      const float pointLength = 0.1;

      void main()
      {
        vec2 pos = gl_FragCoord.xy / resolution.xy;
        pos = pos * 2.0 - 1.0;
        float angle = atan(pos.y / pos.x);
        float timeAngle = TAU * time;

        float d = length(pos);
        float peturb = cos((angle + (timeAngle * d)) * points) * pointLength;

        if (d + peturb < thingSize) {
          float normD = (d + peturb) / thingSize;
          vec4 col2 = vec4(col.g, col.b, col.r, 1.0);
          colour = mix(col, col2, smoothstep(0.45, 1.0, normD));
        }
        else {
          colour = col;
        }
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
  let
    time = prog.id.getUniformLocation("time", true)
    resolution = prog.id.getUniformLocation("resolution", true)

  prog.activate
  resolution.setFloat2 screenWidth.float, screenHeight.float
  
  var
    timePos: float
    timeDir = 1.0
    lastT = epochTime()
  
  template bounce(value: float, limit: Slice[float], dir: float) =
    if value < limit.a:
      value = limit.a
      dir *= -1.0
    if value > limit.b:
      value = limit.b
      dir *= -1.0

  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  while running:
    while pollEvent(evt):
      if evt.kind == QuitEvent:
        running = false
        break
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
    prog.activate
    modelArray.bindArray

    # Update shader with varying time bouncing between 0.0 .. 1.0.
    time.setFloat timePos

    let newT = epochTime()
    timePos += timeDir * (newT - lastT)
    lastT = newT

    timePos.bounce 0.0 .. 1.0, timeDir

    modelVBO.render(1)
    window.glSwapWindow()
