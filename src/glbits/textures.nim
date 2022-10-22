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

    uniform mat4 transform;

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
      float angle = rotation.x;
      mat2 localRot = mat2(cos(angle), sin(angle), -sin(angle), cos(angle));
      position.xy = (localRot * (vertex.xy * scale)) + positionData.xy;
      position.z = positionData.z + vertex.z;

      gl_Position = transform * vec4(position, 1.0);

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

  ## Translation data for instances (e.g., from 'addItems').
  TexBillboardData* = tuple[
    positionData: GLvectorf4,
    colour: GLvectorf4,
    rotation: GLvectorf2, # rotation.x is angle, rotation.y is unused.
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
    manualTextureBo: bool

    bos*: BufferObjects
    rendering*: Rendering
    filteringSampler*: GLuint
    varrayId: GLuint

    transform*: Uniform
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


template withProgram*(tb: TexBillboard, actions: untyped) =
  tb.rendering.program.withProgram:
    actions


template index*[T](tex: var TextureData[T], x, y: int): untyped = ((y * tex.width) + x)


proc dataSize*(tb: TexBillboard): int = tb.count * TexBillboardDataSize


proc len*[T](tex: TextureData[T]): int = tex.width * tex.height


proc initTexture*[T](tex: var TextureData[T], width, height: int) =
  tex.width = width
  tex.height = height
  if not tex.data.isNil: tex.data.dealloc
  tex.data = cast[TextureArrayPtr[T]](alloc0((width * height) * T.sizeOf))


proc clearTexture*[T](tex: var TextureData[T]) =
  if not tex.data.isNil:
    zeroMem(tex.data, (tex.width * tex.height) * T.sizeOf)


proc freeTexture*[T](tex: var TextureData[T]) =
  if tex.data != nil:
    tex.data.deAlloc
    tex.data = nil


proc freeTexture*(tex: var TexBillboard) =
  tex.texture.freeTexture


proc uploadModel*(tb: var TexBillboard) =
  # not wise to call this whilst using a buffer,
  # best to switch buffers and defer one buffer's upload
  glBindVertexArray(tb.varrayId)
  # send model data
  glBindBuffer(GL_ARRAY_BUFFER, tb.bos.modelBO)
  glBufferData(GL_ARRAY_BUFFER, GLsizei(tb.model.len * TextureVertex.sizeOf), tb.modelBuf, GL_STATIC_DRAW) # copy data


proc attachAndLink*(tb: var TexBillboard) =
  template program: untyped = tb.rendering.program

  program.newShaderProgram()
  program.attach tb.rendering.vertex
  program.attach tb.rendering.fragment
  program.link
  program.activate


proc setTransform*(tb: var TexBillboard, matrix: GLmatrixf4) =
  var m = matrix
  tb.withProgram:
    tb.transform.setMat4 m


proc newTexBillboard*(vertexGLSL = defaultTextureVertexGLSL, fragmentGLSL = defaultTextureFragmentGLSL,
    max = 1, model: openarray[TextureVertex] = rectangle, modelScale = 1.0, transform = mat4(1.0),
    manualTextureBo = false, manualProgram = false): TexBillboard =
  ## A container for instanced texture billboards. Use `addItems` or `addFullscreenItem` to add an instance.
  ## By default a program is generated along with a texture that's shared between all instances, defined with `updateTexture`.
  ## You can override this behaviour using the following parameters:
  ##   `manualTextureBo = true`: doesn't populate `bos.textureBO` - useful if you already have a texture id you want to assign.
  ##   `manualProgram = true`: doesn't create a program or fetch uniforms and acts like a simple container.
  ##                           Use with `renderWithProgram` or similar for procedural textures or lighting effects.
  result = new TexBillboard
  result.manualProgram = manualProgram
  result.manualTextureBo = manualTextureBo
  result.count = max
  result.rotMat[0] = c0
  result.rotMat[1] = s0
  result.curItemOffset = 0

  let modelBytes = GLsizei(model.len * TextureVertex.sizeOf)
  result.modelBuf = cast[TexBillboardModelPtr](alloc0(modelBytes))
  result.dataBuf = cast[TexBillboardArrayPtr](alloc0(result.dataSize))

  result.rendering.vertex.newShader(GL_VERTEX_SHADER, vertexGLSL)
  result.rendering.fragment.newShader(GL_FRAGMENT_SHADER, fragmentGLSL)

  template program: untyped = result.rendering.program

  if not manualProgram:
    result.attachAndLink
    result.transform = program.id.getUniformLocation("transform")

  result.model = @[]
  for idx, item in model:
    var scaledItem = item
    scaledItem[0] *= modelScale
    scaledItem[1] *= modelScale
    scaledItem[2] *= modelScale

    result.model.add(scaledItem)
    result.modelBuf[idx] = scaledItem

  # Init sampler for texture.
  glGenSamplers(1, result.filteringSampler.addr)
  glBindSampler(0, result.filteringSampler)
  glSamplerParameteri(result.filteringSampler, GL_TEXTURE_MIN_FILTER, GL_NEAREST )
  glSamplerParameteri(result.filteringSampler, GL_TEXTURE_MAG_FILTER, GL_NEAREST )
  glSamplerParameteri(result.filteringSampler, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  glSamplerParameteri(result.filteringSampler, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

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
    result.texId = program.id.getUniformLocation("tex")

  # setup texture buffer
  if not(manualTextureBo or manualProgram):
    glActiveTexture(GL_TEXTURE0)
    result.texAttribId = result.rendering.program.getAttributeLocation("texcoord")
    glEnableVertexAttribArray(result.texAttribId.GLuint)
    # Texture coords are interlaced with vertex coords.
    glVertexAttribPointer(result.texAttribId.GLuint, 2, cGL_FLOAT, GL_FALSE.GLBoolean, modelDataSize, cast[pointer](GLFloat.sizeOf * 3))

  if not manualProgram:
    glBindBuffer(GL_ARRAY_BUFFER, result.bos.modelBO)
    result.uploadModel
    result.setTransform transform


proc getUniformLocation*(tb: TexBillboard, name: string, allowMissing = false): Uniform =
  tb.rendering.program.id.getUniformLocation(name, allowMissing)


proc manualInit*(tb: var TexBillboard, program: GLuint, customUniforms = true) =
  ## If you have your own program, use this to sync the uniforms required.
  glUseProgram(program)

  program.activateAllAttributes(true)

  if not customUniforms:
    tb.texId = getUniformLocation(program, "tex", true)

  glBindVertexArray(tb.varrayId)
  glBindBuffer(GL_ARRAY_BUFFER, tb.bos.modelBO)
  glBindAttribLocation(program, 5, "texcoord")
  glEnableVertexAttribArray(5)
  glVertexAttribPointer(5, 2, cGL_FLOAT, GL_FALSE.GLBoolean, modelDataSize, cast[pointer](GLFloat.sizeOf * 3)) # shared with vertex coords
  tb.uploadModel


proc resetItemPos*(tb: var TexBillboard) = tb.curItemOffset = 0


proc `[]`*(tb: var TexBillboard, index: int): var TexBillboardData =
  assert index in 0..<tb.count, "Index out of bounds. Given " & $index & ", max: " & $tb.count
  tb.dataBuf[index]


proc uploadItems*(tb: var TexBillboard, indexes: Slice[int]) =
  ## Upload an inclusive range of local instance changes to the GPU.
  glBindBuffer( GL_ARRAY_BUFFER, tb.bos.dataBO )
  glBufferSubData(GL_ARRAY_BUFFER,
    (indexes.a * TexBillboardDataSize).GLintptr,
    (indexes.b - indexes.a + 1) * TexBillboardDataSize.GLsizeiptr,
    tb.dataBuf
  )


proc uploadItems*(tb: var TexBillboard) =
  tb.uploadItems(0 ..< tb.count)


iterator items*(tb: var TexBillboard): var TexBillboardData =
  ## Iterates the current data buffer. Yielded values are mutable.
  for i in 0 ..< tb.count:
    yield tb.dataBuf[i]


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
      # Upload changes to the GPU.
      # TODO: improve cycling behaviour and item management.
      glBindBuffer( GL_ARRAY_BUFFER, tb.bos.dataBO )
      glBufferSubData(GL_ARRAY_BUFFER,
        (startItems * TexBillboardDataSize).GLintptr,
        (tb.curItemOffset - startItems) * TexBillboardDataSize.GLsizeiptr,
        tb.dataBuf
      )


proc addFullScreenItem*(tb: var TexBillboard, zPos: float = 0.0) =
  ## Convenience proc for full screen billboards.
  tb.addItems(1):
    curItem.positionData = vec4(0.0, 0.0, zPos, 1.0)
    curItem.colour = vec4(1.0, 1.0, 1.0, 1.0)
    curItem.rotation = vec2(0.0, 0.0)
    curItem.scale = vec2(1.0, 1.0)


proc updateTexture*(tb: var TexBillboard, sdlTexture = false) =
  glBindTexture(GL_TEXTURE_2D, tb.bos.textureBO)
  if sdlTexture:
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F.GLInt, tb.texture.width.GLsizei, tb.texture.height.GLsizei, 0, GL_BGRA, GL_UNSIGNED_BYTE, tb.texture.data)
  else:
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F.GLInt, tb.texture.width.GLsizei, tb.texture.height.GLsizei, 0, GL_RGBA, cGL_FLOAT, tb.texture.data)


proc updateTexture*(tb: var TexBillboard, newData: pointer, w, h: int, sdlTexture = false, freeOld = true) =
  if freeOld:
    if tb.texture.data != newData and tb.texture.data != nil: tb.texture.data.dealloc
  tb.texture.data = cast[SimpleTextureArrayPtr](newData)
  tb.texture.width = w
  tb.texture.height = h
  tb.updateTexture sdlTexture

  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)


proc updateTexture*(tb: var TexBillboard, newTexture: GLTexture, sdlTexture = false) =
  tb.updateTexture(newTexture.data, newTexture.width, newTexture.height, sdlTexture)


template renderCore(tb: TexBillboard) =
  # bind results and draw
  glBindVertexArray(tb.varrayId)

  if not tb.manualTextureBo:
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, tb.bos.textureBO)
    setInt(tb.texId, 0)

  glEnableClientState(GL_VERTEX_ARRAY)
  debugMsg "Drawing " & $tb.curItemOffset & " models of " & $tb.model.len & " vertices"
  glDrawArraysInstanced( GL_TRIANGLES, 0, tb.model.len.GLSizei, tb.curItemOffset.GLSizei )
  glDisableClientState( GL_VERTEX_ARRAY )


template renderSetup*(tb: TexBillboard, actions: untyped) =
  if not tb.hidden:
    tb.withProgram:
      actions
      renderCore(tb)


proc render*(tb: TexBillboard) =
  ## Render the texture billboard.
  tb.renderSetup:
    discard

template renderWithProgram*(tb: TexBillboard, program: GLuint, actions: untyped): untyped =
  if not tb.hidden:
    glUseProgram(program)
    actions
    renderCore(tb)


template forPixels*[T](tex: var TextureData[T], actions: untyped): untyped =
  var
    px {.inject.}: int
    py {.inject.}: int
    pi {.inject.}: int
  
  for yi in 0 ..< tex.height:
    py = yi
    for xi in 0 ..< tex.width:
      px = xi
      pi = tex.index(xi, yi)
      actions


template forHalfPixels*[T](tex: var TextureData[T], actions: untyped): untyped =
  var
    px {.inject.}: int
    py {.inject.}: int
    pi {.inject.}: int
  
  for yi in 0 ..< tex.height div 2:
    py = yi
    for xi in 0 ..< tex.width:
      px = xi
      pi = tex.index(xi, yi)
      actions


proc reverseY*[T](tex: var TextureData[T]) =
  tex.forHalfPixels:
    let
      newY = tex.height - 1 - py
      newIdx = tex.index(px, newY)
      curValue = tex.data[pi]
    tex.data[pi] = tex.data[newIdx]
    tex.data[newIdx] = curValue


proc reverseX*[T](tex: var TextureData[T]) =
  tex.forHalfPixels:
    let
      newX = tex.width - 1 - px
      newIdx = tex.index(newX, py)
      curValue = tex.data[pi]
    tex.data[pi] = tex.data[newIdx]
    tex.data[newIdx] = curValue


proc reverseXY*[T](tex: var TextureData[T]) =
  tex.forHalfPixels:
    let
      newX = tex.width - 1 - px
      newY = tex.height - 1 - py
      newIdx = tex.index(newX, newY)
      curValue = tex.data[pi]
    tex.data[pi] = tex.data[newIdx]
    tex.data[newIdx] = curValue


# -------------------
# Procedural textures
# -------------------

proc newProcTexture*(fragment: string, max = 1): TexBillboard =
  ## Create a procedural texture using the `fragment` GLSL.
  newTexBillboard(
    manualProgram = false,
    manualTextureBo = true,
    vertexGLSL = defaultTextureVertexGLSL,
    fragmentGLSL = fragment,
    max = max
  )
