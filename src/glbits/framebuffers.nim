import opengl, debugutils, strformat

type
  FrameBuffer* = object
    frameBufferId*: GLuint
    textureIds*: seq[GLuint]
    renderId: GLuint
    attachments: seq[GLuint]

template count*(fb: FrameBuffer): int = fb.textureIds.len

type FrameBufferFormat* = enum fbfFloat, fbfInt

## Shortcut to ref attachment
template colourAttachment*(i: int): GLuint = (GL_COLOR_ATTACHMENT0.int + i).GLuint

proc initFrameBuffer*(fb: var FrameBuffer, width, height: int, bufferTypes: openarray[FrameBufferFormat]) =
  ## Create a set of buffers for the GPU to read/write with.
  glGenFramebuffers(1, fb.frameBufferId.addr)
  debugMsg &"Created frame [buffer {fb.frameBufferId}]"

  glBindFramebuffer(GL_FRAMEBUFFER, fb.frameBufferId)
  debugMsg &" Bound to frame [buffer {fb.frameBufferId}]"

  fb.textureIds = newSeq[GLuint](bufferTypes.len)
  fb.attachments = newSeq[GLuint](bufferTypes.len)

  # Reserve textures.
  debugMsg &" Creating {bufferTypes.len} buffers:"
  for i in 0 ..< bufferTypes.len:
    glGenTextures(1, fb.textureIds[i].addr)
    debugMsg &"  New buffer [texture {fb.textureIds[i]}]"
    glBindTexture(GL_TEXTURE_2D, fb.textureIds[i])

    case bufferTypes[i]
    of fbfInt:
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32UI.GLInt, width.GLsizei, height.GLsizei, 0, GL_RGBA_INTEGER, GL_UNSIGNED_INT, nil)
      debugMsg &"  Set to GL_RGBA_INTEGER [texture {fb.textureIds[i]}]"
    of fbfFloat:
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F.GLInt, width.GLsizei, height.GLsizei, 0, GL_RGBA, cGL_FLOAT, nil)
      debugMsg &"  Set to GL_RGBA [texture {fb.textureIds[i]}]"

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)

    glFramebufferTexture2D(GL_FRAMEBUFFER, (GL_COLOR_ATTACHMENT0.int + i).GLenum, GL_TEXTURE_2D, fb.textureIds[i], 0)
    debugMsg &"  Linked attachment {i} to [texture {fb.textureIds[i]}]"

    fb.attachments[i] = (GL_COLOR_ATTACHMENT0.int + i).GLuint
    
  # depth and stencil buffers
  glGenRenderbuffers(1, fb.renderId.addr)
  debugMsg &" New [render buffer {fb.renderId}]"
  glBindRenderbuffer(GL_RENDERBUFFER, fb.renderId)
  debugMsg &" Binding [render buffer {fb.renderId}]"
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width.GLsizei, height.GLsizei)
  glBindRenderbuffer(GL_RENDERBUFFER, 0)
  # attach depth & stencil buffers to frame buffer
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, fb.renderId);

  # Does the GPU support current FBO configuration?
  var status: GLenum
  status = glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT)
  if status != GL_FRAMEBUFFER_COMPLETE_EXT:
    raise newException(ValueError, "Frame buffer is not complete! Status: " & $status.int)

template bindFrameBuffer*(fb: FrameBuffer): untyped =
  glBindFramebuffer(GL_FRAMEBUFFER, fb.frameBufferId)
  debugMsg &"Bound to frame [buffer {fb.frameBufferId}]"

  # set number of output buffers
  when defined(debugGL):
    var s: string
    for i, a in fb.attachments:
      s &= $(a.int - GL_COLOR_ATTACHMENT0.int)
      if i < fb.attachments.high: s &= ", "
    let str = &"Setting draw buffers for [frame buffer {fb.frameBufferId}] to [" & s & "]"
    debugMsg str
  glDrawBuffers(fb.count.GLsizei, cast[ptr GLenum](fb.attachments[0].addr))

proc setAttachments*(fb: var FrameBuffer, attachments: openarray[GLuint]) =
  glBindFramebuffer(GL_FRAMEBUFFER, fb.frameBufferId)
  # set number of output buffers
  fb.attachments.setLen attachments.len
  for idx, value in attachments:
    fb.attachments[idx] = value
  debugMsg &"Setting draw buffers for [frame buffer {fb.frameBufferId}] to [{fb.attachments}]"
  glDrawBuffers(fb.count.GLsizei, cast[ptr GLenum](fb.attachments[0].addr))

proc clear*(fb: var FrameBuffer) =
  # clear buffer
  fb.bindFrameBuffer
  debugMsg &"Clearing [frame buffer {fb.frameBufferId}]"
  glClearColor(0.0, 0.0, 0.0, 0.0)
  glClearDepth(1.0f)

  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

proc delete*(fb: var FrameBuffer) =
  glDeleteFramebuffers(1, fb.frameBufferId.addr)

type
  PingPongFrameBuffer* = object
    ## A simple double buffered frame buffer to display one, write the other then swap.
    frameBufferIds*: array[0..1, GLuint]
    textureIds*: seq[GLuint]
    renderId: GLuint

proc initFrameBuffers*(fb: var PingPongFrameBuffer, width, height: SomeInteger) =
  ## Generate two frame buffers with a texture each to support reading from texture and writing to the other.
  ## This can be useful for things like bloom and other post-processing effects.
  fb.textureIds = newSeq[GLuint](2)
  debugMsg &"Creating ping pong frame buffer."
  for i in 0 ..< fb.frameBufferIds.len:
    glGenFramebuffers(1, fb.frameBufferIds[i].addr)
    debugMsg &" Created [frame buffer {fb.frameBufferIds[i]}]"
    glBindFramebuffer(GL_FRAMEBUFFER, fb.frameBufferIds[i])
    debugMsg &" Bound to [frame buffer {fb.frameBufferIds[i]}]"
    glGenTextures(1, fb.textureIds[i].addr)
    debugMsg &" New [texture {fb.textureIds[i]}]"
    glBindTexture(GL_TEXTURE_2D, fb.textureIds[i])
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F.GLInt, width.GLsizei, height.GLsizei, 0, GL_RGBA, cGL_FLOAT, nil)
    debugMsg &" Set to GL_RGBA [texture {fb.textureIds[i]}]"

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

    # Both buffers are colour attachment zero.
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, fb.textureIds[i], 0)
    debugMsg &" Linked attachment 0 to [texture {fb.textureIds[i]}]"

  # depth and stencil buffers
  glGenRenderbuffers(1, fb.renderId.addr)
  debugMsg &" New [render buffer {fb.renderId}]"
  glBindRenderbuffer(GL_RENDERBUFFER, fb.renderId)
  debugMsg &" Binding [render buffer {fb.renderId}]"
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width.GLsizei, height.GLsizei)
  glBindRenderbuffer(GL_RENDERBUFFER, 0)
  # attach depth & stencil buffers to frame buffer
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, fb.renderId);

  # Does the GPU support current FBO configuration?
  var status: GLenum
  status = glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT)
  if status != GL_FRAMEBUFFER_COMPLETE_EXT:
    raise newException(ValueError, "Frame buffer is not complete! Status: " & $status.int)

proc clear*(fb: var PingPongFrameBuffer, bufId: int) =
  # clear buffer
  debugMsg &"Clearing [frame buffer {fb.frameBufferIds[bufId]}]"
  glBindFramebuffer(GL_FRAMEBUFFER, fb.frameBufferIds[bufId])
  glClearColor(0.0, 0.0, 0.0, 0.0)
  glClearDepth(1.0f)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

proc getCurrentFrameBuffer*: GLint =
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, result.addr)
