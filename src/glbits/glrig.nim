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
  SDLButton* = uint8
  SDLButtons* = set[uint8]

  SDLDisplay* = object
    x*, y*, w*, h*: cint
    res*: tuple[x, y: cint]
    aspect*: float
    fullScreen*: bool
    changed*: bool

  SDLMouseChangeKind* = enum mcPosition, mcButton, mcButtonUp, mcButtonDown, mcWheel, mcWheelInc, mcWheelDec
  SDLMousePosDiff* = object
    sx*, sy*: cint
    gl*: GLvectorf2

  SDLMouseChange* = object
    kinds*: set[SDLMouseChangeKind]
    pos*: SDLMousePosDiff
    buttons*: tuple[down, up: SDLButtons]
    wheel*: MouseWheelEventObj

  SDLMousePos* = object
    sx*, sy*: cint
    gl*: GLvectorf2
    buttons*: SDLButtons
    changes*: SDLMouseChange

  KeyCodes = ptr array[0 .. SDL_NUM_SCANCODES.int, uint8]

func changed*(mp: SDLMousePos): bool = mp.changes.kinds.len > 0

proc normalise*(sdlDisplay: SDLDisplay, pos: array[2, int | cint]): GLvectorf2 =
  ## Convert a screen pixel coordinate to an OpenGl normalised -1.0 .. 1.0.

  let
    n = [
      pos[0].float32 / sdlDisplay.res.x.float32,
      pos[1].float32 / sdlDisplay.res.y.float32
    ]

  result[0] = (n[0] * 2.0 - 1.0)
  result[1] = (1.0 - n[1]) * 2.0 - 1.0


template normalize*(sdlDisplay: SDLDisplay, pos: array[2, int | cint]): GLvectorf2 =
  ## Convert a screen pixel coordinate to an OpenGl normalised -1.0 .. 1.0.
  normalise(sdlDisplay, pos)


func update*(sdlDisplay: var SDLDisplay) =
  sdlDisplay.fullScreen = sdlDisplay.w == sdlDisplay.res.x and sdlDisplay.h == sdlDisplay.res.y
  assert sdlDisplay.h != 0, "Zero height for display: " & $sdlDisplay
  sdlDisplay.aspect = sdlDisplay.w / sdlDisplay.h


func pressed*(keyStates: KeyCodes, sc: Scancode): bool =
  keyStates[sc.int] > 0'u8


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
    sdlDisplay* {.inject.} =
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
    sdlWindow* {.inject.} = createWindow("SDL/OpenGL Skeleton", sdlDisplay.x, sdlDisplay.y, sdlDisplay.w, sdlDisplay.h, windowFlags)
    sdlContext* {.inject, used.} = sdlWindow.glCreateContext()


  # Initialize OpenGL
  loadExtensions()

  glEnable(GL_DEPTH_TEST)                           # Enable depth testing for z-culling
  glClearDepth(1.0)                                 # Set background depth to farthest
  glDepthFunc(GL_LEQUAL)                            # Set the type of depth-test
  glDepthMask(GL_TRUE)
  glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST);  

  glEnable(GL_BLEND)                                # Enable alpha channel
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  glClearColor(0.0, 0.0, 0.0, 0.0)                  # Set background color to transparent black


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
      running {.inject, used.} = true
      event {.inject, used.} = sdl2.defaultEvent
      mouseInfo {.inject, used.}: SDLMousePos
      keyStates {.inject, used.}: KeyCodes = getKeyboardState()

    while running:
      sdlDisplay.changed = false
      mouseInfo.changes = default(SDLMouseChange)

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

            let
              nX = mm.x.GLfloat / sdlDisplay.w.GLfloat
              nY = 1.0 - (mm.y.GLfloat / sdlDisplay.h.GLfloat)
              gl = [(nX * 2.0'f32) - 1.0'f32, (nY * 2.0'f32) - 1.0'f32]

            mouseInfo.changes.kinds.incl mcPosition
            mouseInfo.changes.pos.sx = mm.x - mouseInfo.sx
            mouseInfo.changes.pos.sy = mm.y - mouseInfo.sy
            mouseInfo.changes.pos.gl = [mouseInfo.gl[0] - gl[0], mouseInfo.gl[1] - gl[1]]

            mouseInfo.gl = gl
            mouseInfo.sx = mm.x
            mouseInfo.sy = mm.y

          of MouseButtonDown:
            var mb = evMouseButton(event)
            mouseInfo.changes.kinds.incl mcButton
            mouseInfo.changes.kinds.incl mcButtonDown
            mouseInfo.changes.buttons.down.incl mb.button
            mouseInfo.buttons.incl mb.button
          
          of MouseButtonUp:
            var mb = evMouseButton(event)
            mouseInfo.changes.kinds.incl mcButton
            mouseInfo.changes.kinds.incl mcButtonUp
            mouseInfo.changes.buttons.up.incl mb.button
            mouseInfo.buttons.excl mb.button

          of MouseWheel:
            mouseInfo.changes.wheel = evMouseWheel(event)[]
            mouseInfo.changes.kinds.incl mcWheel
            if mouseInfo.changes.wheel.y >= 0:
              mouseInfo.changes.kinds.incl mcWheelInc
            else:
              # SDL_MOUSEWHEEL_FLIPPED:
              mouseInfo.changes.kinds.incl mcWheelDec
          
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

