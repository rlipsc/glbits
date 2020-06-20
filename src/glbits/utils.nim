import opengl, macros

from math import round, `mod`

template vec2*(x, y: float|float32): GLvectorf2 = [x.GLfloat, y]
template vec3*(x, y, z: float|float32): GLvectorf3 = [x.GLfloat, y, z]
template vec4*(r, g, b, a: float|float32): GLvectorf4 = [r.GLfloat, g, b, a]

template vec2*(v: float|float32): GLvectorf2 = [v.GLfloat, v]
template vec3*(v: float|float32): GLvectorf3 = [v.GLfloat, v, v]
template vec4*(v: float|float32): GLvectorf4 = [v.GLfloat, v, v, v]

template x*(v: GLvectorf2 | GLvectorf3 | GLvectorf4): float = v[0]
template y*(v: GLvectorf2 | GLvectorf3 | GLvectorf4): float = v[1]
template z*(v: GLvectorf3 | GLvectorf4): float = v[2]
template w*(v: GLvectorf3 | GLvectorf4): float = v[3]

template xy*(v: GLvectorf3): GLvectorf2 = vec2(v[0], v[1])
template xyz*(v: GLvectorf4): GLvectorf3 = vec3(v[0], v[1], v[2])
template a*(v: GLvectorf4): GLfloat = v.w

macro makeOps(ty: typedesc[array]): untyped =
  ## Builds `+`, `-`, `*`, `/`, `+=`, `-=`, `*=`, and `/=` operators
  ## for array types.
  let
    impl = ty.getImpl
    len = impl[2][1][2].intVal
    a = ident "a"
    b = ident "b"
  result = newStmtList()
  for opStr in ["+", "-", "*", "/"]:
    let
      op = nnkAccQuoted.newTree(ident opStr)
      opEq = nnkAccQuoted.newTree(ident opStr & "=")
    var
      opNative = nnkBracket.newTree()
      opTyFloat = nnkBracket.newTree()
      opFloatTy = nnkBracket.newTree()
      opEqNative = newStmtList()
      opEqFloat = newStmtList()
      
    for i in 0 .. len:
      opNative.add(quote do: `op`(`a`[`i`], `b`[`i`]))
      opTyFloat.add(quote do: `op`(`a`[`i`], `b`))
      opFloatTy.add(quote do: `op`(`a`, `b`[`i`]))
      opEqNative.add(quote do: `opEq`(`a`[`i`], `b`[`i`]))
      opEqFloat.add(quote do: `opEq`(`a`[`i`], `b`))
      
    result.add(quote do:
      func `op`*(`a`, `b`: `ty`): `ty` {.inline,noInit.} = `opNative`
      func `op`*(`a`: `ty`, `b`: GLfloat): `ty` {.inline,noInit.}  = `opTyFloat`
      func `op`*(`a`: GLfloat, `b`: `ty`): `ty` {.inline,noInit.}  = `opFloatTy`
      func `opEq`*(`a`: var `ty`, `b`: `ty`) {.inline,noInit.} = `opEqNative`
      func `opEq`*(`a`: var `ty`, `b`: GLfloat) {.inline,noInit.}  = `opEqFloat`
    )

makeOps GLvectorf2
makeOps GLvectorf3
makeOps GLvectorf4

template mix*(x, y, a: float|GLfloat): float =
  ## Mix two floats according to `a`.
  x * (1 - a) + y * a

proc mix*[N: static[int], T: array[N, GLfloat]](v1, v2: T, a: GLfloat): T {.inline.} =
  ## Mix two arrays of floats together according to `a`.
  for i in 0 ..< N:
    result[i] = v1[i] * (1 - a) + v2[i] * a

proc mix*(value: float, items: openarray[GLVectorf4]): GLVectorf4 =
  ## Mix over a set of colours with a normalised `value`.
  assert value in 0.0..1.0, "Value out of range: got " & $value & ", expected 0..1"
  let
    i2 = round(value * items.high.float).int
    i1 = max(0, i2 - 1)
    fracPerItem = 1.0 / items.len.float
    valueIntoItem = value mod fracPerItem
    normIntoItem = valueIntoItem / fracPerItem
  items[i1].mix(items[i2], normIntoItem)

func smootherStep*(a, b, r: float): float =
  var r = clamp(r, 0.0, 1.0)
  r = r * r * r * (r * (6.0 * r - 15.0) + 10.0)
  mix(a, b, r)

template forLine*(x1, y1, x2, y2: float|GLfloat, steps: int, actions: untyped): untyped =
  ## Interpolate between two points in a line.
  block:
    let
      dist = vec2(x2 - x1, y2 - y1)
      stepX {.inject.} = dist[0] / steps.float
      stepY {.inject.} = dist[1] / steps.float
    var
      xCoord {.inject.} = x1    # current X
      yCoord {.inject.} = y1    # current Y
      nXCoord {.inject.}: float # next X
      nYCoord {.inject.}: float # next Y
      lineIdx {.inject.}: int   # iteration count
    for i in 0 ..< steps:
      lineIdx = i
      nXCoord = xCoord + stepX
      nYCoord = yCoord + stepY

      actions

      xCoord = nXCoord
      yCoord = nYCoord

template forLine*(start, finish: GLvectorf2, steps: int, actions: untyped): untyped =
  ## Interpolate between two points in a line.
  forLine(start[0], start[1], finish[0], finish[1], steps):
    actions

template forElectricLine*(x1, y1, x2, y2: float|GLfloat, steps: int, variance: float, actions: untyped): untyped =
  ## Interpolate between two points in a line with a cumulative random deviation.
  block:
    let
      dist = vec2(x2 - x1, y2 - y1)
      stepX {.inject.} = dist[0] / steps.float
      stepY {.inject.} = dist[1] / steps.float
      maxHVar = variance / 2
      midI = steps div 2
      dx = x2-x1
      dy = y2-y1
    var
      xCoord {.inject.} = x1
      yCoord {.inject.} = y1
      lineIdx {.inject.}: int
      lineXCoord = x1
      lineYCoord = y1
      hVar: float
      iDist: int
      curOffset: float
      normal = vec2(-dy, dx).normalise
      lastOffset, r: float

    # generate line points
    for i in 0 ..< steps:
      if i < midI:
        iDist = midI - i
      else:
        iDist = i - midI
      hVar = (1 - (iDist.float / steps.float)) * variance
      lineXCoord += stepX
      lineYCoord += stepY
      r = rand(-0.01..0.01)
      curOffset += r
      curOffset = clamp(curOffset, -hVar, hVar)

      xCoord = lineXCoord + normal[0] * curOffset
      yCoord = lineYCoord + normal[1] * curOffset
      lastOffset = curOffset

      lineIdx = i

      actions
