# glbits

This library provides a very light interface to OpenGL shaders, vertex buffer objects, and vertex array objects. It has no dependencies other than OpenGL.

Running `src/glbits/glbits.nim` itself demonstrates how to draw a coloured triangle with a simple shader. To make the window handling simpler, this demonstration uses `SDL2.dll` which can be obtained [here](https://www.libsdl.org/download-2.0.php). `SDL2.dll` is not required for general use of `glbits`.

Whilst `glbits` It is intended to be built upon, a ready to use example model renderer is included which allows performant rendering of model instances with independent positions, colours, scales, and 2D rotations. This can be used with:

    import glbits/modelrenderer

Expected output from running `glbits` as the main module:

https://user-images.githubusercontent.com/36367371/124191338-90528a00-dabb-11eb-8b20-2ae3ed9d9ed5.mp4
