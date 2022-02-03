import sdl2, sdl2/ttf, glbits/textures, opengl

## Simple font renderer using texture billboards and sdl2.ttf.

type
  ## Renders a font to a texture.
  TextCache* = object
    texBB: TexBillboard
    texBBPosition: GLvectorf3
    texBBScale: GLvectorf2
    texBBAngle: float
    texBBColour: GLvectorf4
    font*: FontPtr
    fontText: string
    fontAngle: float
    texture: TexturePtr
    fontWidth: cint
    fontHeight: cint
    fontOutline: cint


proc updateTexBB*(tc: var TextCache) =
  tc.texBB.resetItemPos
  tc.texBB.addItems(1):
    curItem.positionData = [tc.texBBPosition[0], tc.texBBPosition[1], tc.texBBPosition[2], 1.0]
    curItem.colour = tc.texBBColour
    curItem.rotation[0] = tc.fontAngle
    curItem.scale = tc.texBBScale


proc `uniformScale=`*(tc: var TextCache, scale: float) = tc.texBBScale = [scale.GLfloat, scale]

from math import cos, sin, round


proc initTextCache*(): TextCache =
  result.texBB = newTexBillboard()
  result.uniformScale = 1.0
  result.texBBColour = [1.0.GLfloat, 1.0, 1.0, 1.0]
  result.texBB.rotMat[0] = cos(0.0)
  result.texBB.rotMat[1] = sin(0.0)
  result.updateTexBB


proc deallocate*(tc: TextCache) =
  if tc.texture != nil:
    tc.texture.destroy


proc toSDLColour*(glColour: GLvectorf4): Color =
  # sdl colour cannot exceed 255
  result.r = (255.0 * clamp(glColour[0], 0.0, 1.0)).round.uint8
  result.g = (255.0 * clamp(glColour[1], 0.0, 1.0)).round.uint8
  result.b = (255.0 * clamp(glColour[2], 0.0, 1.0)).round.uint8
  result.a = (255.0 * clamp(glColour[3], 0.0, 1.0)).round.uint8


template doLocked(surface: SurfacePtr, actions: untyped): untyped =
  if SDL_MUSTLOCK(surface):
    # Lock the surface
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
  
  assert tc.font != nil, "Font is not initialised"
  let
    col = toSDLColour(tc.texBBColour)

  tc.font.setFontOutline(tc.fontOutline)
  
  var
    surface = tc.font.renderUtf8Blended(tc.fontText.cstring, col)
  
  if surface.isNil:
    echo "Could not render text surface"
    quit(1)
  
  discard surface.setSurfaceAlphaMod(col.a)
  
  # TODO: Give option to update the model so that text extends rather than squishes

  var
    newTex: SDLTexture # note: not initialised
  
  surface.doLocked:
    newTex.data = cast[SimpleSDLTextureArrayPtr](surface.pixels)
    newTex.width = surface.w
    tc.fontWidth = surface.w
    newTex.height = surface.h
    tc.fontHeight = surface.h
    newTex.reverseY
    tc.texBB.updateTexture(surface.pixels, surface.w , surface.h, sdlTexture = true, freeOld = false)
  
  tc.updateTexBB
  freeSurface(surface)


proc staticLoadFont*(filename: static[string]): FontPtr =
  ## filename must be available at compile-time.

  template staticReadRW(filename: string): ptr RWops =
    const file = staticRead(filename)
    rwFromConstMem(file.cstring, file.len)

  result = openFontRW(staticReadRW(filename), freeSrc = 1, 24)
  if result == nil:
    echo "ERROR: Failed to load font"
    echo getError()


proc col*(tc: TextCache): GLvectorf4 = tc.texBBColour


proc `col=`*(tc: var TextCache, col: GLvectorf4) =
  if tc.texBBColour != col:
    tc.texBBColour = col
    tc.updateTexBB


proc `offset=`*(tc: var TextCache, offset: GLvectorf2) =
  tc.texBB.offset = offset


proc position*(tc: TextCache): GLvectorf3 = tc.texBBPosition


proc `position=`*(tc: var TextCache, pos: GLvectorf3) =
  if tc.texBBPosition != pos:
    tc.texBBPosition = pos
    tc.updateTexBB


proc `position=`*(tc: var TextCache, pos: GLvectorf2) =
  ## just update x, y
  if tc.texBBPosition[0] != pos[0] or tc.texBBPosition[1] != pos[1]:
    tc.texBBPosition[0] = pos[0]
    tc.texBBPosition[1] = pos[1]
    tc.updateTexBB


proc setZ*(tc: var TextCache, zPos: float) =
  if tc.texBBPosition[2] != zPos:
    tc.texBBPosition[2] = zPos
    tc.updateTexBB


proc scale*(tc: TextCache): GLvectorf2 = tc.texBBScale


proc `scale=`*(tc: var TextCache, scale: GLvectorf2) =
  if tc.texBBScale != scale:
    tc.texBBScale = scale
    tc.updateTexBB


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


proc width*(tc: TextCache): cint = tc.fontWidth


proc height*(tc: TextCache): cint = tc.fontHeight


proc normalisedFontSize*(tc: TextCache, screenRes: GLvectorf2): GLVectorf2 {.inline.} =
  # calculate from screenRes and fontSize to give axis' of (0..1)
  # we divide screen res by 2 because GL screens are between -1.0..1.0
  result[0] = tc.fontWidth.float / (screenRes[0] * 2)
  result[1] = tc.fontHeight.float / (screenRes[1] * 2)


proc `size=`*(tc: var TextCache, size: tuple[w: cint, h: cint]) =
  if tc.fontWidth != size.w or tc.fontHeight != size.h:
    tc.fontWidth = size.w
    tc.fontHeight = size.h
    if tc.fontText != "":
      tc.renderFont


proc updateText*(tc: var TextCache, textStr: string) =
  if textStr != tc.fontText:
    tc.fontText = textStr
    tc.renderFont


proc updateText*(tc: var TextCache, textStr: string, x, y: GLfloat) =
  tc.position = [x, y]
  tc.updateText(textStr)


proc updateText*(tc: var TextCache, textStr: string, x, y: GLfloat, scale: GLvectorf2) =
  tc.position = [x, y]
  tc.scale = scale
  tc.updateText(textStr)


proc text*(tc: TextCache): string = tc.fontText


proc `text=`*(tc: var TextCache, text: string) =
  tc.updateText(text)


proc render*(tc: var TextCache) =
  tc.updateTexBB
  tc.texBB.render
