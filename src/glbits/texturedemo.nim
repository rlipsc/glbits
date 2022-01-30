import sdl2, times, random, glbits, utils, textures, math, glrig

initSdlOpenGl(1200, 1400)

proc createBallTexture(texture: var GLTexture, w, h = 120) =
  ## Create a ball texture.
  texture.initTexture(w, h)

  proc dist(x1, y1, x2, y2: float): float =
    let
      diffX = x2 - x1
      diffY = y2 - y1
    result = sqrt((diffX * diffX) + (diffY * diffY))

  let
    centre = [texture.width / 2, texture.height / 2]
    maxDist = dist(centre[0], centre[1], texture.width.float, texture.height.float)

  for y in 0 ..< texture.height:
    for x in 0 ..< texture.width:
      let
        ti = texture.index(x, y)
        diff = [centre[0] - x.float, centre[1] - y.float]
        d = sqrt((diff[0] * diff[0]) + (diff[1] * diff[1]))
        normD = d / maxDist
        edgeDist = smootherStep(1.0, 0.0, normD)
      
      texture.data[ti] = vec4(edgeDist, edgeDist, edgeDist, edgeDist)


proc mainLoop() =
  const
    max = 1_000_000 # Instances.
    dt = 1.0 / 60.0
  let
    targetFramePeriod: uint32 = 20
  var
    ballTexture: GLTexture

  # Draw on the texture.
  ballTexture.createBallTexture()

  var
    texBillboard = newTexBillboard(
      defaultTextureVertexGLSL,
      defaultTextureFragmentGLSL,
      max = max,
      renderAspect = sdlDisplay.aspect)

  # Send the texture to the GPU.
  texBillboard.updateTexture(ballTexture)

  const
    screenRange = -2.0 .. 2.0
    sizeRange = 0.002 .. 0.006
    moveRange = -0.005 .. 0.005

  # Add some instances of the texture to the billboard.
  texBillboard.addItems(max):
    curItem.positionData =  vec4(rand(screenRange), rand(screenRange), 0.0, 1.0)
    curItem.colour =        vec4(rand(1.0), rand(1.0), rand(1.0), 1.0)

    let
      ang = rand TAU
      size = rand(sizeRange)
      spinSpeed = 5.0.degToRad
    
    curItem.rotation[0] = ang
    curItem.rotation[1] = rand(-spinSpeed .. spinSpeed)
    curItem.scale =       vec2(size)

  let
    maxVel = 40.0.degToRad
  var
    angle: float
    turnVel = 0.0.degToRad
    turnAccl = 0.0
  
  # SDL2 polling loop.
  pollEvents:
    if sdlDisplay.changed:
      texBillboard.updateAspect sdlDisplay.aspect

    # Render.
    doubleBuffer:
      # Set billboard render angle.
      texBillboard.rotMat[0] = cos(angle)
      texBillboard.rotMat[1] = sin(angle)
      # Render texture instances.
      texBillboard.render

    # Update some of the instance positions in the buffer.
    let
      updateCount = 10_000
      start = rand(0 ..< texBillboard.count - updateCount)
      updateSlice = start .. start + updateCount

    for i in updateSlice:
      texBillboard[i].positionData[0] += rand(moveRange)
      texBillboard[i].positionData[1] += rand(moveRange)
    
    # Send the updated buffer to the GPU.
    texBillboard.uploadItems

    # Randomly change the billboard's rotational acceleration.
    if rand(1.0) < 0.01:
      turnAccl = rand -maxVel..maxVel

    turnVel *= 0.99
    turnVel += turnAccl * dt
    angle += turnVel * dt

mainLoop()
