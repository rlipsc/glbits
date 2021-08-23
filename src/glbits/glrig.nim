## Quickly set up an interactable OpenGL window using SDL2.
## 
## Example:
## 
##    import sdl2, opengl
##  
##    initSdlOpenGl()
##  
##    # Simple render loop.
## 
##    pollEvents:
##      # Code here is run every loop.
## 
##      # Mouse movement and quit events are pre-handled.
##      if mouseInfo.changed:
##        echo "New mouse info ", mouseInfo
## 
##      if not running:
##        echo "Received a quit event"
##
##      if keyStates.pressed(SDL_SCANCODE_SPACE):
##        echo "Space bar is pressed"
## 
##      doubleBuffer:
##        # Clears the colour and depth buffers then runs the code here.
##        # The front and back buffers are then swapped.
##        discard
##
##
##    # Handle other events by passing another code block:
## 
##    pollEvents:
##      # Events other than quit and mouse movement are in the injected
##      # 'event' variable.
##      echo "Event received :", event
## 
##    do:
##      # Code here is run every loop.
##
##      doubleBuffer:
##        discard
##

import sdl2, opengl

type
  SDLDisplay* = object
    x*, y*, w*, h*: cint
    res*: tuple[x, y: cint]
    aspect*: float
    fullScreen*: bool
    changed*: bool
  
  SDLMousePos* = object
    sx*, sy*: cint
    gl*: tuple[x, y: GLfloat]
    changed*: bool

  KeyCodes = ptr array[0 .. SDL_NUM_SCANCODES.int, uint8]

func update*(sdlDisplay: var SDLDisplay) =
  sdlDisplay.fullScreen = sdlDisplay.w == sdlDisplay.res.x and sdlDisplay.h == sdlDisplay.res.y
  assert sdlDisplay.h != 0, "Zero height for display: " & $sdlDisplay
  sdlDisplay.aspect = sdlDisplay.w / sdlDisplay.h

func pressed*(keyStates: KeyCodes, sc: Scancode): bool = keyStates[sc.int] > 0'u8

template initSdlOpenGl*(width = 640.cint, height = 480.cint, xOffset = 50.cint, yOffset = 60.cint, setFullScreen = false) =
  ## Create window and OpenGL context.
  ## 
  ## Injects the following variables to the scope:
  ##    - `sdlDisplay: SDLDisplay` holds the position and dimensions of the
  ##      display. This is updated when the user changes the size of the
  ##      window.
  ##    - `sdlWindow: WindowPtr` is returned by `sdl2.createWindow`.
  ##    - `context: GlContextPtr` is returned by `sdl2.glCreateContext(sdlWindow)`.
  when not declared(sdl2):
    {.fatal: "glrig needs sdl2 to be imported".}
    
  when not declared(opengl):
    {.fatal: "glrig needs opengl to be imported".}
    
  discard sdl2.init(INIT_EVERYTHING)

  var
    dm: DisplayMode
    getRes = getDesktopDisplayMode(0, dm)
    getResSuccess = getRes == SdlSuccess
  
  if not getResSuccess:
    raise newException(Exception, "SDL_GetDesktopDisplayMode failed: " & getRes.repr & ": " & $getError())

  var
    sdlDisplay {.inject.} =
      if setFullScreen:
        SDLDisplay(x: 0, y: 0, w: dm.w, h: dm.h, changed: true)
      else:
        SDLDisplay(x: xOffset, y: yOffset, w: width, h: height, changed: true)
    windowFlags {.genSym.} =
      if setFullScreen:
        SDL_WINDOW_OPENGL or SDL_WINDOW_FULLSCREEN_DESKTOP
      else:
        SDL_WINDOW_OPENGL or SDL_WINDOW_RESIZABLE

  sdlDisplay.res.x = dm.w
  sdlDisplay.res.y = dm.h
  sdlDisplay.update

  let
    sdlWindow {.inject.} = createWindow("SDL/OpenGL Skeleton", sdlDisplay.x, sdlDisplay.y, sdlDisplay.w, sdlDisplay.h, windowFlags)
    sdlContext {.inject, used.} = sdlWindow.glCreateContext()


  # Initialize OpenGL
  loadExtensions()
  glClearColor(0.0, 0.0, 0.0, 1.0)                  # Set background color to black and opaque
  glClearDepth(1.0)                                 # Set background depth to farthest
  glEnable(GL_DEPTH_TEST)                           # Enable depth testing for z-culling
  glDepthFunc(GL_LEQUAL)                            # Set the type of depth-test
  glEnable(GL_BLEND)                                # Enable alpha channel
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)


template pollEvents*(events, actions: untyped) =
  ## Poll SDL2 events while executing `actions` until a quit event is
  ## received.
  ## 
  ## This template expects `initSdlOpenGl` to have been run.
  ## 
  ## The following three events are handled:
  ## 
  ##  1) The mouse movement event:
  ##    The updated mouse position is stored in the `mouseInfo` variable:
  ##    - `mouseInfo.gl` is set to the normalised -1.0..1.0 coordinates.
  ##    - `mouseInfo.changed` is `true` during an iteration where an update has occurred.
  ## 
  ##  2) The display resize event: updates the `sdlDisplay` variable created
  ##    by `initSdlOpenGl`:
  ##    - `sdlDisplay.aspectRatio` is recalculated.
  ##    - `sdlDisplay.fullScreen` is `true` when the display width and height match `sdlDisplay.res`.
  ##    - `sdlDisplay.changed` is `true` during an iteration where an update has occurred.
  ##    - Invokes `glViewPort` with the new dimensions.
  ## 
  ##  3) The quit event: sets `running` to `false`, causing the loop to exit.
  ## 
  ## The `events` block is run when a new event is received from `sdl2.pollEvent`.
  ## Within this block the injected `event: Event` variable stores the
  ## active event`.
  ## 
  ## The `actions` block is run each iteration of the loop, after any events
  ## have been processed.
  ## 
  ## The following fields are available in both code blocks:
  ## 
  ##    - `running: bool`: initialised to `true`, the loop will run until
  ##      this is `false`.
  ## 
  ##    - `mouseInfo: SDLMousePos`: stores the last update from the mouse
  ##      motion event.
  ## 
  ##    - `keyStates: KeyCodes`: lets you access the keyboard state using
  ##      the `pressed` template.
  ## 
  block:
    var
      running {.inject.} = true
      event {.inject.} = sdl2.defaultEvent
      mouseInfo {.inject.}: SDLMousePos
      keyStates {.inject.}: KeyCodes = getKeyboardState()

    while running:
      mouseInfo.changed = false
      sdlDisplay.changed = false

      while pollEvent(event):

        case event.kind
          of QuitEvent:
            running = false

          of WindowEvent:
            var
              windowEvent = cast[WindowEventPtr](addr(event))
            
            if windowEvent.event == WindowEvent_Resized:
              
              sdlDisplay.w = windowEvent.data1
              sdlDisplay.h = windowEvent.data2
              
              sdlDisplay.changed = true
              sdlDisplay.update

              glViewport(0, 0, sdlDisplay.w, sdlDisplay.h)

          of MouseMotion:
            # Map SDL mouse position to -1..1 for OpenGL.
            let mm = evMouseMotion(event)
            mouseInfo.sx = mm.x
            mouseInfo.sy = mm.y
            mouseInfo.changed = true
            let
              nX = mm.x.float / sdlDisplay.w.float
              nY = 1.0 - (mm.y.float / sdlDisplay.h.float)
            mouseInfo.gl.x = (nX * 2.0) - 1.0
            mouseInfo.gl.y = (nY * 2.0) - 1.0
          
          else:
            # User events.
            events
      
      actions


template pollEvents*(actions: untyped) =
  ## Polls the SDL2 event loop, handling quit events, mouse movement,
  ## and keyboard state access.
  ## 
  ## Exits when the injected `running` variable is `false` by the user
  ## or a quit event.
  pollEvents:
    discard
  do: actions


template doubleBuffer*(actions: untyped) =
  ## Clear the display buffer, run `actions`, then show the buffer.
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

  actions

  glFlush()
  sdlWindow.glSwapWindow()


when isMainModule:
  import sdl2, opengl

  initSdlOpenGl()
  echo "Display settings: ", sdlDisplay

  pollEvents:

    # Process events that aren't quit, resize, or mouse motion.
    echo "Event received :", event

  do:
    # Code here is run every loop.

    if keyStates.pressed(SDL_SCANCODE_SPACE):
      echo "Space bar is pressed"

    if mouseInfo.changed:
      echo "New mouse info ", mouseInfo
    
    if sdlDisplay.changed:
      echo "Resized: ", sdlDisplay
    
    if not running:
      echo "Received a quit event"

    doubleBuffer:
      # Rendering run here will draw to a freshly cleared back buffer
      # that is swapped to the display when the block finishes.
      #
      # This helps to avoid visual artifacts from half rendered scenes.
      discard
