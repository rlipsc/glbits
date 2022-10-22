# glbits

This library provides a lightweight interface for working with OpenGL shaders and SDL2.

## OpenGL

- Create and manage vertex array and buffer objects
- Easily build custom shader programs
- Allow GLSL code to 'include' local files and build a GLSL library
- Adds arithmetic overloads for GL vector and matrix types
- Use GL vectors like GLSL: `echo length(mix(vec2(1, 2), vec2(1), 0.5) + vec2(3, 4) - 1)`
- Useful colour utilities: `assert vec4(1).brighten(0.5).withAlpha(0.1) == vec4(0.5, 0.5, 0.5, 0.1)`
- Utilities for calculating angles, normals, dots and crosses, perspective, and working with pixels
- Fast instanced model and texture rendering

## SDL2

- Create windows and contexts
- Easily poll events for things like mouse and keyboard
- Render fonts to OpenGL textures

Running `src/glbits/glbits.nim` itself demonstrates how to draw a coloured triangle with a simple shader. To make the window handling simpler, this demonstration uses `SDL2.dll` which can be obtained [here](https://www.libsdl.org/download-2.0.php). `SDL2.dll` is not required for general use of `glbits`.

Expected output from running `glbits` as the main module:

https://user-images.githubusercontent.com/36367371/124191338-90528a00-dabb-11eb-8b20-2ae3ed9d9ed5.mp4

A demo of instanced texture rendering with 200,000 textures and global rotation is provided in `texturedemo.nim`:

https://user-images.githubusercontent.com/36367371/124296615-128d8d80-db52-11eb-8d50-d4efbd130d8a.mp4

## Set up interactable SDL2/OpenGL windows

This example creates an interactable window and displays any mouse, keyboard, and other SDL2 events.

```nim
import sdl2, opengl, glbits

# Create SDL/OpenGL window and context variables.
initSdlOpenGl()
echo "Display settings: ", sdlDisplay

pollEvents:
  # Quit, resize, and mouse motion events are handled for you and
  # applied to 'running', 'mouseInfo' and 'keyStates' variables.
  # Code here is run for any other SDL2 event.
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
```

## GL utilities

Importing glbits lots of utilities for working with OpenGL types for productivity and efficiency.

### Sugar for common OpenGL types

```nim
# 'vec2' -> 'GLvectorf2', 'vec3' -> 'GLvectorf3', 'vec4' -> 'GLvectorf4'.
# 'mat4' -> 'GLmatrixf4'
let
  pos = vec2(1, 3.5)    # Shortcut for [1.GLfloat, 3.5.GLfloat] AKA 'GLVectorf2'.
  col = vec4(0.5)       # Set all components at once.
  m1 = mat4(vec4(1, 2, 3, 4), vec4(5, 6, 7, 8), vec4(9, 10, 11, 12), vec4(13, 14, 15, 16))
  m2 = mat4(vec4(2, 3, 4, 5), vec4(6, 7, 8, 9), vec4(10, 11, 12, 13), vec4(14, 15, 16, 17))

assert vec3(1, 2, 3) + vec3(1, 2, 3) + 2 == vec3(4, 6, 8)
# Access components with x, y, z, w
assert pos.y == 3.5'f32
# or as r, g, b, a.
assert col.y == col.g

assert mat4(1) == identity[4]() # Passing a single value to mat4 sets the main diagonal.

assert (m1 + m2) == mat4(
  vec4(3, 5, 7, 9),
  vec4(11, 13, 15, 17),
  vec4(19, 21, 23, 25),
  vec4(27, 29, 31, 33)
)
```

You can apply the arithmetic overloads to other array types with `makeOps`. This can be useful for example for `int`:

```nim
type Int3 = array[3, int]
makeOps Int3
assert [1, 2, 3] + [1, 2, 3] + 2 == [4, 6, 8]
```

### Working with buffers

The core of the library is the `VertexArrayObject`, which groups an array of `VertexBufferObject` data.

These objects are used to interact with the GPU, such as defining vertex positions, colours, and other data. Buffers are then consumed by a `ShaderProgram` to render to the screen, off screen to a `FrameBuffer`, or processing with compute.

Buffers are accessed using `asArray(N)` where `N` is the number of `GLfloat` components that make up the array item.

For convenience, the `addData` procedure applies `asArray` based on the parameter data type.

Note: these are unchecked operations and buffers that are initialised to the wrong size are not detected.

To allocate a buffer from data, use `initVbo`:

```nim
proc addModel(vao: VertexArrayObject, vertices: openarray[GLvectorf3) =
  vao.add initVBO(0.GLuint, vertices)
```


To get a copy of a buffer's data, use `getData`. This can be useful for cloning buffers, for instance to copy an existing model's vertices.

## 3D model rendering

The core of the library is an interface for vertex arrays and buffer objects for working with shaders.

A ready to use [example model renderer](https://github.com/rlipsc/glbits/blob/master/src/glbits/modelrenderer.nim) is included which allows performant rendering of model instances with independent positions, colours, scales, and 2D rotations.

This renderer can be used for general purpose 3D model rendering with default or custom shaders:

```nim
import glbits, glbits/modelrenderer, os

proc initShaders* =
  let
    thisDir = currentSourcePath().parentDir
    
    # Create a new program with the default vertex/fragment shader GLSL.
    simpleShader = newModelRenderer()

    # Read in GLSL and process include comments.
    vertShader = readAndInclude(thisDir.joinPath r"myVertexShader.glsl", echoOutput = false)
    fragShader = readAndInclude(thisDir.joinPath r"myFragmentShader.glsl", echoOutput = false)
    
    # Create a shader program with the loaded GLSL.
    customShader = newShaderProgramId(vertShader, fragShader)
  
    # Create a simple circle model using baseShader.
    circleModel = baseShader.makeCircleModel(
      triangles = 8,
      # These vertex colours get mixed with the instance colour with default shaders.
      insideCol = vec4(1.0),
      outsideCol = vec4(0.3, 0.3, 0.3, 1.0),
      maxInstances = 1000
    )
```

The `modelrenderer` module is really just setting up some buffers for a default shader, and serves as a template for more specific shader layouts.

For instance, to add a buffer for normals, we could easily extend `newModel`:

```nim
import glbits, glbits/modelrenderer

export modelrenderer except newModel, renderModel, renderModels

proc newModel*(shaderProgramId: ShaderProgramId, vertices: openarray[GLvectorf3], colours: openarray[GLvectorf4], normals: openarray[GLvectorf3]): ModelId =
  var
    normals = initVBO(6, normals) # Create a buffer object and read the normal data.

  # ... previous 0-5 buffer adds.
  vao.add normals # Add new buffer to the shader's vertex array object.

  # ... as before, the vao is stored and returns the index to you.
  models.add ModelStorage(programId: shaderProgramId, vao: vao)
  result = models.high.ModelId
```

Then we can calculate the model's normals with `triangleNormals`.

```nim
import glbits, mymodelrenderer, mymodeldata

let myModelId = myShaderProg.newModel(myVertices, myColours, myVertices.triangleNormals)
```

## Texture rendering

Textures are handled through a `TexBillboard` object which is designed to draw multiple instances.

```nim
import sdl2, glbits, random

initSdlOpenGl(800, 600)

# Create texture.
var texture: GLTexture
texture.initTexture(100, 100)
# Edit the texture's pixels.
for y in 0 ..< texture.height:
  for x in 0 ..< texture.width:
    let ti = texture.index(x, y)
    texture.data[ti] = vec4(rand 1.0)

# Create rendering billboard.
let maxItems = 100
var texBillboard = newTexBillboard(max = maxItems)

# Send the texture to the GPU.
texBillboard.updateTexture(texture)

# Set up 'maxItems' instances of the texture.
texBillboard.addItems(maxItems):
  curItem.positionData =  vec4(rand(-1.0..1.0), rand(-1.0..1.0), 0.0, 1.0)
  curItem.colour =        vec4(rand(1.0), rand(1.0), rand(1.0), 1.0)
  curItem.scale =         vec2(0.05)

pollEvents:
  doubleBuffer:
    # Render instances of the texture.
    texBillboard.render
```

For a more in depth example, see the `demons/texturedemo.nim`.

## Fonts

Fonts are handled with a `TextCache` object.

This uses `SDL2/ttf` to render text with a font to a `TexBillboard`.

TTF font rendering is comparatively slow, so the font is only rendered if the text is changed, otherwise the cached texture is used.


