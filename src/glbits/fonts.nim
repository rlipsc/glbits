import sdl2, sdl2/ttf, glbits/textures, opengl

## Simple font renderer using instanced texture billboards and sdl2.ttf.

type
  ## Renders a font to a texture.
  TextCache* = object
    texBB: TexBillboard
    texBBPosition: GLvectorf3
    texBBScale, texScale: GLvectorf2
    texBBAngle: float
    texBBColour: GLvectorf4
    font*: FontPtr
    fontText: string
    needsRender: bool
    fontAngle: float
    fontOutline*: cint
    resolution*: GLvectorf2


func isCustomScale*(tc: TextCache): bool = tc.texBBScale != [0.0'f32, 0.0'f32]


proc updateTexBB*(tc: var TextCache) =
  tc.texBB.resetItemPos
  tc.texBB.addItems(1):
    curItem.positionData = [tc.texBBPosition[0], tc.texBBPosition[1], tc.texBBPosition[2], 1.0]
    curItem.colour = tc.texBBColour
    curItem.rotation[0] = tc.fontAngle
    if tc.isCustomScale:
      curItem.scale = tc.texBBScale
    else:
      curItem.scale = tc.texScale


from math import cos, sin, round


proc initTextCache*(): TextCache =
  result.texBB = newTexBillboard()
  result.texBBColour = [1.0.GLfloat, 1.0, 1.0, 1.0]
  result.texBB.rotMat[0] = cos(0.0)
  result.texBB.rotMat[1] = sin(0.0)
  result.updateTexBB
  result.needsRender = true


proc freeTexture*(tc: var TextCache) =
  tc.texBB.freeTexture


proc setTransform*(tc: var TextCache, matrix: GLmatrixf4) =
  tc.texBB.setTransform matrix


proc toSDLColour*(glColour: GLvectorf4): Color =
  # SDL colour cannot exceed 255.
  result.r = (255.0 * clamp(glColour[0], 0.0, 1.0)).round.uint8
  result.g = (255.0 * clamp(glColour[1], 0.0, 1.0)).round.uint8
  result.b = (255.0 * clamp(glColour[2], 0.0, 1.0)).round.uint8
  result.a = (255.0 * clamp(glColour[3], 0.0, 1.0)).round.uint8


template doLocked(surface: SurfacePtr, actions: untyped): untyped =
  if SDL_MUSTLOCK(surface):
    # Lock the surface.
    if surface.lockSurface() == 0:
      actions
      surface.unlockSurface()
    else:
      echo "ERROR: Could not lock surface."
      quit(1)
  else:
    actions

proc renderFont*(tc: var TextCache) =
  ## Renders the font to the texture cache.
  
  assert not tc.font.isNil, "Font is not initialised"
  tc.font.setFontOutline(tc.fontOutline)
  tc.needsRender = false
  
  let
    col = toSDLColour(tc.texBBColour)
    text =
      # An empty string won't create a surface to upload so a space is used.
      if tc.fontText.len == 0: " ".cstring
      else: tc.fontText.cstring
  
  var surface = renderUtf8Blended(tc.font, text, col)
  if surface.isNil:
    assert false, "Could not render font text to surface"
    return
  
  discard surface.setSurfaceAlphaMod(col.a)
  var newTex: SDLTexture # note: not initialised, used for casting.
  
  let
    textureScale =
      if not tc.isCustomScale:
        assert tc.resolution[0] > 0'f32 and tc.resolution[1] > 0'f32,
          "Provide non-zero dimensions to 'resolution' or use 'setFixedScale' to render a TextCache"
        let nScale = [surface.w.float32 / tc.resolution[0], surface.h.float32 / tc.resolution[1]]
        # [nScale[0] * 2'f32, nScale[1] * 2'f32]
        nScale
      else:
        tc.texBBScale

  assert textureScale[0] != 0.0,
    "Rendering font text returned a zero size: " & $textureScale

  surface.doLocked:
    newTex.data = cast[SimpleSDLTextureArrayPtr](surface.pixels)
    newTex.width = surface.w
    newTex.height = surface.h
    # Reflect the font texture pixels on the Y axis for OpenGL.
    newTex.reverseY

    # Note: the texture memory is freed after upload.
    tc.texBB.updateTexture(surface.pixels, surface.w, surface.h, sdlTexture = true, freeOld = false)
    tc.texScale = textureScale
    tc.updateTexBB

  freeSurface(surface)
  tc.texBB.texture.data = nil


func renderedScale*(tc: TextCache): GLvectorf2 = tc.texScale


proc staticLoadFont*(filename: static[string], pointSize = 24.cint): FontPtr =
  ## File must be available at compile-time.

  template staticReadRW(filename: string): ptr RWops =
    const file = staticRead(filename)
    rwFromConstMem(file.cstring, file.len)

  result = openFontRW(staticReadRW(filename), freeSrc = 1, pointSize)
  if result == nil:
    echo "Error: Failed to load font: ", getError()


proc col*(tc: TextCache): GLvectorf4 = tc.texBBColour


proc `col=`*(tc: var TextCache, col: GLvectorf4) =
  if tc.texBBColour != col:
    tc.texBBColour = col


proc `offset=`*(tc: var TextCache, offset: GLvectorf2) =
  tc.texBB.offset = offset


proc position*(tc: TextCache): GLvectorf3 = tc.texBBPosition


proc `position=`*(tc: var TextCache, pos: GLvectorf3) =
  if tc.texBBPosition != pos:
    tc.texBBPosition = pos


proc `position=`*(tc: var TextCache, pos: GLvectorf2) =
  ## just update x, y
  if tc.texBBPosition[0] != pos[0] or tc.texBBPosition[1] != pos[1]:
    tc.texBBPosition[0] = pos[0]
    tc.texBBPosition[1] = pos[1]


proc setZ*(tc: var TextCache, zPos: float) =
  if tc.texBBPosition[2] != zPos:
    tc.texBBPosition[2] = zPos


proc fixedScale*(tc: TextCache): GLvectorf2 = tc.texBBScale


proc setFixedScale*(tc: var TextCache, scale: GLvectorf2) =
  if tc.texBBScale != scale:
    tc.texBBScale = scale


proc globalRotation*(tc: TextCache): GLvectorf2 =
  tc.texBB.rotMat


proc `globalRotation=`*(tc: var TextCache, value: GLvectorf2) =
  tc.texBB.rotMat = value


proc `globalRotation=`*(tc: var TextCache, angle: float) =
  tc.texBB.rotMat = [cos angle.GLfloat, sin angle]


proc fontAngle*(tc: var TextCache): float =
  tc.fontAngle


proc `fontAngle=`*(tc: var TextCache, angle: float) =
  tc.fontAngle = angle


proc scale*(tc: TextCache): GLvectorf2 = tc.renderedScale


proc text*(tc: TextCache): string = tc.fontText


proc `text=`*(tc: var TextCache, text: string) =
  if text != tc.fontText:
    tc.fontText = text
    tc.needsRender = true


proc renderText*(tc: var TextCache, force = false) =
  if force or tc.needsRender:
    tc.renderFont


func needsRender*(tc: TextCache): bool = tc.needsRender


proc update*(tc: var TextCache, textStr: string, x, y: GLfloat, force = false) =
  tc.text = textStr
  tc.position = [x, y]
  tc.renderText(force)


proc update*(tc: var TextCache, textStr: string, x, y: GLfloat, fixedScale: GLvectorf2, force = false) =
  tc.setFixedScale fixedScale
  tc.update(textStr, x, y, force)


proc render*(tc: var TextCache) =
  ## Renders the font text to a texture if necessary,
  ## then draws the texture to the frame buffer.
  if tc.needsRender:
    tc.renderText
  tc.updateTexBB
  tc.texBB.render
