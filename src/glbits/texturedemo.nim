import sdl2, times, random, glbits, utils, textures, math

discard sdl2.init(INIT_EVERYTHING)

var screenWidth: cint = 1200
var screenHeight: cint = 1000

var window = createWindow("SDL/OpenGL Skeleton", 100, 100, screenWidth, screenHeight, SDL_WINDOW_OPENGL or SDL_WINDOW_RESIZABLE)
var context = window.glCreateContext()
#var renderer =createRenderer(window, -1, Renderer_Accelerated or Renderer_PresentVsync or Renderer_TargetTexture)

# Initialize OpenGL
loadExtensions()
glClearColor(0.0, 0.0, 0.0, 1.0)                  # Set background color to black and opaque
glClearDepth(1.0)                                 # Set background depth to farthest
glEnable(GL_DEPTH_TEST)                           # Enable depth testing for z-culling
glEnable(GL_BLEND)                                # Enable alpha channel
glEnable(GL_TEXTURE_COORD_ARRAY)
glEnable(GL_TEXTURE_2D)
glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
glDepthFunc(GL_LEQUAL)                            # Set the type of depth-test
glShadeModel(GL_SMOOTH)                           # Enable smooth shading

proc reshape(newWidth: cint, newHeight: cint) =
  glViewport(0, 0, newWidth, newHeight)   # Set the viewport to cover the new window
  glMatrixMode(GL_PROJECTION)             # To operate on the projection matrix
  glLoadIdentity()                        # Reset
  #gluPerspective(45.0, newWidth / newHeight, 0.1, 100.0)  # Enable perspective projection with fovy, aspect, zNear and zFar

proc limitFrameRate(frameTime: var uint32, target: uint32) =
  let now = getTicks()
  if frameTime > now:
    delay(frameTime - now) # Delay to maintain steady frame rate
  frameTime += target

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
  let
    targetFramePeriod: uint32 = 20 # 20 milliseconds corresponds to 50 fps
  var
    frameTime: uint32 = 0
    curFrameTime = epochTime()
    lastFrameTime = epochTime()
    dt = curFrameTime - lastFrameTime
    ballTexture: GLTexture
  
  ballTexture.createBallTexture()

  reshape(screenWidth, screenHeight) # Set up initial viewport and projection

  const max = 200_000
  var
    evt = sdl2.defaultEvent
    runGame = true
    texBillboard = newTexBillboard(defaultTextureVertexGLSL, defaultTextureFragmentGLSL, max = max)

  # Big one in the middle.
  texBillboard.addItems(1):
    curItem.positionData =  vec4(0.0, 0.0, 0.0, 1.0)
    curItem.colour =        vec4(1.0, 0.0, 0.0, 1.0)
    curItem.rotation =      vec2(cos(0.0), sin(0.0))
    curItem.scale =         vec2(1.0, 1.0)

  # Scatterings of instances across the screen.
  const
    screenRange = -2.0 .. 2.0
    sizeRange = 0.005 .. 0.0125

  texBillboard.addItems(max - 1):
    curItem.positionData =  vec4(rand(screenRange), rand(screenRange), 0.0, 1.0)
    #curItem.colour =        vec4(1.0, rand(0.5), rand(0.2), 1.0)
    curItem.colour =        vec4(rand(1.0), rand(1.0), rand(1.0), 1.0)
    let
      ang = rand TAU
      size = rand(sizeRange)
      spinSpeed = 5.0.degToRad
    
    curItem.rotation[0] = ang
    curItem.rotation[1] = rand(-spinSpeed .. spinSpeed)
    curItem.scale =       vec2(size)

  texBillboard.updateTexture(ballTexture)

  let maxVel = 40.0.degToRad
  var
    angle: float
    turnVel = 0.0.degToRad
    turnAccl = 0.0
  while runGame:
    while pollEvent(evt):
      if evt.kind == QuitEvent:
        runGame = false
        break
      if evt.kind == WindowEvent:
        var windowEvent = cast[WindowEventPtr](addr(evt))
        if windowEvent.event == WindowEvent_Resized:
          let newWidth = windowEvent.data1
          let newHeight = windowEvent.data2
          reshape(newWidth, newHeight)

    # Clear color and depth buffers
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

    lastFrameTime = curFrameTime
    curFrameTime = epochTime()
    dt = curFrameTime - lastFrameTime

    texBillboard.rotMat[0] = cos(angle)
    texBillboard.rotMat[1] = sin(angle)
    texBillboard.render

    if rand(1.0) < 0.01: turnAccl = rand -maxVel..maxVel

    turnVel *= 0.99
    turnVel += turnAccl * dt
    angle += turnVel * dt
    
    limitFrameRate(frameTime, targetFramePeriod)
    window.glSwapWindow() # Swap the front and back frame buffers (double buffering)

mainLoop()
