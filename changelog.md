# GLBits

## v0.1.5 2022-2-3

Added:
  - SDL2 font support with `TextCache`. This uses a `TexBillboard` to
    render text to a texture which can then be rendered.
  - `dot` product function.
  - `reflect` function.
  - `asLength` to return a value from the in-place `setLength`.
  - Add `taxiCabAngle` function.
  - Generated array operators now include `abs` and `<=`. The latter
    enables `>=` and `min`/`max` for arrays.

Changed:

- When passed texture data `updateTexture` now defaults to freeing the
  existing texture before assigning the new one.
- `normalise` functionality now works with the `SDLDisplay` type.
- `constrain`: uses `GLvector` instead of `openarray`.
- Unroll `sqrLen`.

## v0.1.4 2021-12-4

Added:
  - `glRig` module provides templates to quickly create an interactive
    graphics application with OpenGL and SDL2.
  - `makeRectangleModel` creates a coloured rectangle model.

Fixed:
  - `texturedemo.nim` incorrect bounds for spinSpeed.

## v0.1.3 2021-8-14

- Added:
  - `makePolyModel` allows construction of polygon models.
  - `rotate2d` and `rotated2d` utility procs.
  - `clearTexture` proc.

## v0.1.2 2021-4-18

- Added:
  - Framebuffer support.
  - Output detailed debug messages when compiling with `-d:debugGL`.

- Changed:
  - `models.nim` is now `modelrenderer.nim`.
  - `init` for `VertexBufferObject` now takes the index for the buffer.

## v0.1.1 2020-5-6

- Added:
  - `mix` to blend between colours and arrays of floats.
  - You can now run model shader programs individually.

- Fixed:
  - Model rotation is now clockwise.

## v0.1.0 2020-4-6

- Initial version supporting rendering with VBOs and shaders.
