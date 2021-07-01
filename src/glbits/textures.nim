import opengl, glbits, utils, uniforms, debugutils

#[
  Render instanced textures.
]#

const
  defaultTextureVertexGLSL* = """
    #version 450
    layout(location = 0) in vec4 positionData;
    layout(location = 1) in vec4 colour;
    layout(location = 2) in vec2 rotation;
    layout(location = 3) in vec2 scale;
    layout(location = 4) in vec3 vertex;

    uniform vec2 globalOffset;
    uniform vec2 globalRotation;

    in vec2 texcoord;
    out vec4 FragCol;
    out vec2 Texcoord;

    mat3 rotMatZ(vec2 rotVec)
    {
      return mat3(rotVec.x, -rotVec.y, 0,
                  rotVec.y, rotVec.x, 0,
                  0, 0, 1);
    }

    mat4 rotMatZ2(vec2 rotVec)
    {
      return mat4(rotVec.x, -rotVec.y, 0, 0,
                  rotVec.y, rotVec.x, 0, 0,
                  0, 0, 1, 0,
                  0, 0, 0, 1);
    }

    void main()
    {

      vec3 position;
      // NB: rotation.x is angle, rotation.y is unused.
      mat2 localRot = mat2(cos(rotation.x), -sin(rotation.x), sin(rotation.x), cos(rotation.x));
      position.xy = (localRot * (vertex.xy * scale)) + positionData.xy;
      position.z = positionData.z + vertex.z;

      vec2 p = vec2(position.x, position.y) + globalOffset;
      mat2 globalRot = mat2(globalRotation.x,-globalRotation.y, globalRotation.y, globalRotation.x);
      p = globalRot * p;
      
      gl_Position = vec4(p, position.z, 1.0f);

      FragCol = colour;
      Texcoord = texcoord;
    }
  """
  defaultTextureFragmentGLSL* = """
    #version 330 core
    in vec4 FragCol;
    in vec2 Texcoord;

    layout (location = 0) out vec4 colour;

    uniform sampler2D tex;

    void main()
    {
        colour = texture(tex, Texcoord) * FragCol;
    }
  """

const
  c0 = 1.0
  s0 = 0.0
type
  TextureArrayPtr*[T] = ptr UncheckedArray[T]

  TexturePixel* = GLVectorf4
  SDLTexturePixel* = uint32

  TextureData*[T] = object
    data*: TextureArrayPtr[T]
    width*: int
    height*: int

  GLTexture* = TextureData[TexturePixel]
  SDLTexture* = TextureData[SDLTexturePixel]

  SimpleTextureArrayPtr* = TextureArrayPtr[TexturePixel]
  SimpleSDLTextureArrayPtr* = TextureArrayPtr[SDLTexturePixel]

  AnyTexture* = GLTexture | SDLTexture

  TextureProc* = proc(texture: var GLTexture)

  TexBillboardData* = tuple[
    positionData: GLvectorf4,
    colour: GLvectorf4,
    rotation: GLvectorf2,
    scale: GLvectorf2
  ]

  ## Texture coordinates: x, y, z, u, v
  TextureVertex* = array[5, GLfloat]

  TextureModelPtr* = ptr UncheckedArray[TextureVertex]
  TexBillboardArrayPtr* = ptr UncheckedArray[TexBillboardData]
  TexBillboardModelPtr* = ptr UncheckedArray[TextureVertex]

  BufferObjects = object
    textureBO*: GLuint
    modelBO: GLuint
    dataBO: GLuint

  Rendering = object
    vertex: Shader
    fragment: Shader
    program*: ShaderProgram

  TexBillboard* = ref object
    manualProgram: bool
    bos*: BufferObjects
    rendering*: Rendering
    linearFilteringSampler: GLuint
    varrayId: GLuint
    offsetId*: Uniform
    rotMatId*: Uniform
    texId: Uniform
    texture*: GLTexture
    texAttribId: Attribute
    model: seq[TextureVertex]
    modelBuf*: TexBillboardModelPtr
    dataBuf*: TexBillboardArrayPtr
    count*: int
    curItemOffset*: int
    lastItemOffset: int
    rotMat*: GLvectorf2
    offset*: GLvectorf2
    scale*: float
    hidden*: bool # turns off rendering when set

let
  TexBillboardDataSize*: GLsizei = TexBillboardData.sizeof.GLsizei
  modelDataSize*: GLsizei = TextureVertex.sizeOf().GLsizei

const rectangle: array[6, TextureVertex] = [
  [-1.0.GLFloat, 1.0, 0.0,    0.0, 1.0],
  [1.0.GLFloat, 1.0, 0.0,     1.0, 1.0],
  [-1.0.GLFloat, -1.0, 0.0,   0.0, 0.0],
  #
  [1.0.GLFloat, -1.0, 0.0,    1.0, 0.0],
  [-1.0.GLFloat, -1.0, 0.0,   0.0, 0.0],
  [1.0.GLFloat, 1.0, 0.0,     1.0, 1.0]
]

proc programId*(tb: TexBillboard): GLuint = tb.rendering.program.id

template index*[T](tex: var TextureData[T], x, y: int): untyped = ((y * tex.width) + x)
proc dataSize*(tb: TexBillboard): int = tb.count * TexBillboardDataSize
proc len*[T](tex: TextureData[T]): int = tex.width * tex.height

proc initTexture*[T](tex: var TextureData[T], width, height: int) =
  tex.width = width
  tex.height = height
  if not tex.data.isNil: tex.data.dealloc
  tex.data = cast[TextureArrayPtr[T]](alloc0((width * height) * T.sizeOf))

proc freeTexture*[T](tex: var TextureData[T]) =
  if tex.data != nil: tex.data.deAlloc
  tex.data = nil

proc uploadModel*(tb: var TexBillboard) =
  # not wise to call this whilst using a buffer,
  # best to switch buffers and defer one buffer's upload
  glBindVertexArray(tb.varrayId)
  # send model data
  glBindBuffer(GL_ARRAY_BUFFER, tb.bos.modelBO)
  glBufferData(GL_ARRAY_BUFFER, GLsizei(tb.model.len * TextureVertex.sizeOf), tb.modelBuf, GL_STATIC_DRAW) # copy data

proc newTexBillboard*(vertexGLSL = defaultTextureVertexGLSL, fragmentGLSL = defaultTextureFragmentGLSL,
    max = 1, model: openarray[TextureVertex] = rectangle, modelScale = 1.0, manualTextureBo = false, manualProgram = false): TexBillboard =
  ## A container for instanced texture billboards. Use `addItems` or `addFullscreenItem` to add an instance.
  ## By default a program is generated along with a texture that's shared between all instances, defined with `updateTexture`.
  ## You can override this behaviour using the following parameters:
  ##   `manualTextureBo = true`: Doesn't populate `bos.textureBO` - useful if you already have a texture id you want to assign.
  ##   `manualProgram = true`: Doesn't create a program or fetch uniforms and acts like a simple container.
  ##                           Use with `renderWithProgram` or similar for procedural textures or lighting effects.
  ## (for instance for procedural generation with a shader)
  result = new TexBillboard
  result.manualProgram = manualProgram
  result.count = max
  result.rotMat[0] = c0
  result.rotMat[1] = s0
  result.curItemOffset = 0

  let modelBytes = GLsizei(model.len * TextureVertex.sizeOf)
  result.modelBuf = cast[TexBillboardModelPtr](alloc0(modelBytes))
  result.dataBuf = cast[TexBillboardArrayPtr](alloc0(result.dataSize))

  result.rendering.vertex.newShader(GL_VERTEX_SHADER, vertexGLSL)
  result.rendering.fragment.newShader(GL_FRAGMENT_SHADER, fragmentGLSL)

  if not manualProgram:
    # Program init.
    template program: untyped = result.rendering.program
    program.newShaderProgram()
    program.attach result.rendering.vertex
    program.attach result.rendering.fragment
    program.link
    program.activate
    result.offsetId =       program.id.getUniformLocation("globalOffset")
    result.rotMatId =       program.id.getUniformLocation("globalRotation")
    result.texId =          program.id.getUniformLocation("tex")

  result.model = @[]
  for idx, item in model:
    var scaledItem = item
    scaledItem[0] *= modelScale
    scaledItem[1] *= modelScale
    scaledItem[2] *= modelScale

    result.model.add(scaledItem)
    result.modelBuf[idx] = scaledItem

  # Init sampler for texture.
  glGenSamplers(1, result.linearFilteringSampler.addr)
  glBindSampler(0, result.linearFilteringSampler)
  glSamplerParameteri(result.linearFilteringSampler, GL_TEXTURE_MIN_FILTER, GL_NEAREST )
  glSamplerParameteri(result.linearFilteringSampler, GL_TEXTURE_MAG_FILTER, GL_NEAREST )
  glSamplerParameteri(result.linearFilteringSampler, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  glSamplerParameteri(result.linearFilteringSampler, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

  glGenVertexArrays(1, result.varrayId.addr)
  glBindVertexArray(result.varrayId)

  # define buffer for render items
  glGenBuffers( 1, result.bos.dataBO.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.bos.dataBO)
  # allocate buffer memory
  glBufferData(GL_ARRAY_BUFFER, result.dataSize, nil, GL_DYNAMIC_DRAW )

  # Attributes for each instance.
  glEnableVertexAttribArray(0)
  glEnableVertexAttribArray(1)
  glEnableVertexAttribArray(2)
  glEnableVertexAttribArray(3)
  glVertexAttribPointer(0, 4, cGL_FLOAT, GL_FALSE.GLBoolean, TexBillboardDataSize, nil)
  glVertexAttribPointer(1, 4, cGL_FLOAT, GL_FALSE.GLBoolean, TexBillboardDataSize, cast[pointer](GLVectorf4.sizeOf))
  glVertexAttribPointer(2, 2, cGL_FLOAT, GL_FALSE.GLBoolean, TexBillboardDataSize, cast[pointer](GLVectorf4.sizeOf * 2))
  glVertexAttribPointer(3, 2, cGL_FLOAT, GL_FALSE.GLBoolean, TexBillboardDataSize, cast[pointer]((GLVectorf4.sizeOf * 2) + GLVectorf2.sizeOf))
  glVertexAttribDivisor(0, 1) # per instance
  glVertexAttribDivisor(1, 1) # per instance
  glVertexAttribDivisor(2, 1) # per instance
  glVertexAttribDivisor(3, 1) # per instance

  # Set up model vertices.
  glGenBuffers( 1, result.bos.modelBO.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.bos.modelBO)
  glEnableVertexAttribArray(4)
  # Model indices are interlaced with tex coords.
  glVertexAttribPointer(4, 3, cGL_FLOAT, GL_FALSE.GLBoolean, modelDataSize, nil)
  glVertexAttribDivisor(4, 0) # per vertex

  if not manualTextureBo:
    # Create texture buffer
    glGenTextures(1, result.bos.textureBO.addr)

  glActiveTexture(GL_TEXTURE0)
  # setup texture buffer
  if not manualProgram:
    result.texAttribId = result.rendering.program.getAttributeLocation("texcoord")
    glBindBuffer(GL_ARRAY_BUFFER, result.bos.modelBO)
    glEnableVertexAttribArray(result.texAttribId.GLuint)
    # Texture coords are interlaced with vertex coords.
    glVertexAttribPointer(result.texAttribId.GLuint, 2, cGL_FLOAT, GL_FALSE.GLBoolean, modelDataSize, cast[pointer](GLFloat.sizeOf * 3))
    result.uploadModel

proc getUniformLocation*(tb: TexBillboard, name: string, allowMissing = false): Uniform =
  tb.rendering.program.id.getUniformLocation(name, allowMissing)

proc manualInit*(tb: var TexBillboard, program: GLuint) =
  ## If you have your own program, use this to sync the uniforms required.
  glUseProgram(program)

  program.activateAllAttributes(true)

  tb.offsetId = getUniformLocation(program, "globalOffset", true)
  tb.rotMatId = getUniformLocation(program, "globalRotation", true)
  tb.texId = getUniformLocation(program, "tex", true)

  glBindVertexArray(tb.varrayId)
  glBindBuffer(GL_ARRAY_BUFFER, tb.bos.modelBO)
  glBindAttribLocation(program, 5, "texcoord")

  glEnableVertexAttribArray(5)
  glVertexAttribPointer(5, 2, cGL_FLOAT, GL_FALSE.GLBoolean, modelDataSize, cast[pointer](GLFloat.sizeOf * 3)) # shared with vertex coords
  tb.uploadModel

proc resetItemPos*(tb: var TexBillboard) = tb.curItemOffset = 0

template addItems*(tb: var TexBillboard, amount: int, actions: untyped): untyped =
  ## Adds billboard instances.
  ## Within `actions` the following variables can be accessed:
  ##   `curItem`: The current instance being added defined with `TexBillboardData`.
  ##   `index`: How far through `amount` we are.
  ## Returns immediately if curItemOffset >= maxItems.
  ## When the last item is reached you must call resetItemPos to write again
  assert tb.curItemOffset < tb.count
  if tb.curItemOffset < tb.count:
    var
      startItems = tb.curItemOffset
      bufIdx = 0
      i = 0
    while tb.curItemOffset < tb.count and i < amount:
      var curItem {.inject.}: TexBillboardData
      let index {.inject, used.} = i

      actions

      tb.dataBuf[bufIdx] = curItem
      bufIdx += 1
      tb.curItemOffset += 1
      i += 1

    if tb.curItemOffset - startItems > 0:
      # upload changes
      glBindBuffer( GL_ARRAY_BUFFER, tb.bos.dataBO )
      glBufferSubData(GL_ARRAY_BUFFER, (startItems * TexBillboardDataSize).GLintptr, (tb.curItemOffset - startItems) * TexBillboardDataSize.GLsizeiptr, tb.dataBuf)

proc addFullScreenItem*(tb: var TexBillboard, zPos: float = 0.0) =
  ## Convenience proc for full screen billboards.
  tb.addItems(1):
    curItem.positionData = vec4(0.0, 0.0, zPos, 1.0)
    curItem.colour = vec4(1.0, 1.0, 1.0, 1.0)
    curItem.rotation = vec2(0.0, 0.0)
    curItem.scale = vec2(1.0, 1.0)

proc updateTexture*(tb: var TexBillboard, sdlTexture = false) =
  glBindTexture(GL_TEXTURE_2D, tb.bos.textureBO)
  assert(tb.texture.data != nil)
  if sdlTexture:
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F.GLInt, tb.texture.width.GLsizei, tb.texture.height.GLsizei, 0, GL_BGRA, GL_UNSIGNED_BYTE, tb.texture.data)
  else:
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F.GLInt, tb.texture.width.GLsizei, tb.texture.height.GLsizei, 0, GL_RGBA, cGL_FLOAT, tb.texture.data)

proc updateTexture*(tb: var TexBillboard, newData: pointer, w, h: int, sdlTexture = false, freeOld = false) =
  if freeOld:
    if tb.texture.data != newData and tb.texture.data != nil: tb.texture.data.dealloc
  tb.texture.data = cast[SimpleTextureArrayPtr](newData)
  tb.texture.width = w
  tb.texture.height = h
  tb.updateTexture

  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

proc updateTexture*(tb: var TexBillboard, newTexture: GLTexture, sdlTexture = false) =
  tb.updateTexture(newTexture.data, newTexture.width, newTexture.height, sdlTexture)

template renderCore(tb: TexBillboard, program: GLuint) =
  tb.offsetId.setVec2 tb.offset
  tb.rotMatId.setVec2 tb.rotMat

  # bind results and draw
  glBindVertexArray(tb.varrayId)

  if not tb.manualProgram:
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, tb.bos.textureBO)
    setInt(tb.texId, 0)

  glEnableClientState(GL_VERTEX_ARRAY)
  debugMsg "Drawing " & $tb.curItemOffset & " models of " & $tb.model.len & " vertices"
  glDrawArraysInstanced( GL_TRIANGLES, 0, tb.model.len.GLSizei, tb.curItemOffset.GLSizei )

  glDisableClientState( GL_VERTEX_ARRAY )

template withProgram*(tb: TexBillboard, actions: untyped) =
  tb.rendering.program.withProgram:
    actions

proc render*(tb: TexBillboard) =
  # render
  # upload offsets
  if not tb.hidden:
    tb.withProgram:
      tb.renderCore(tb.rendering.program.id)

template renderSetup*(tb: TexBillboard, actions: untyped) =
  if not tb.hidden:
    tb.withProgram:
      actions
      renderCore(tb, tb.rendering.program.id)

template renderWithProgram*(tb: TexBillboard, program: GLuint, actions: untyped): untyped =
  if not tb.hidden:
    glUseProgram(program)    
    actions
    renderCore(tb, program)
