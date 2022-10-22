import opengl, macros, random

from math import round, `mod`, sqrt, cos, sin, tan, arcTan2, PI, TAU, floor


## Utility routines: swizzling, named access to indexes, and operators for
## basic math on GL vectors.


type
  GLVector* = GLvectorf2|GLvectorf3|GLvectorf4

# Using `SomeInteger|SomeFloat` rather than `SomeNumber` allows different
# types per parameter, e.g., `vec2(1, 2.3)`.

template vec2*(x, y: SomeInteger|SomeFloat): GLvectorf2 = [x.GLfloat, y.GLfloat]
template vec3*(x, y, z: SomeInteger|SomeFloat): GLvectorf3 = [x.GLfloat, y.GLfloat, z.GLfloat]
template vec4*(r, g, b, a: SomeInteger|SomeFloat): GLvectorf4 = [r.GLfloat, g.GLfloat, b.GLfloat, a.GLfloat]
template vec4*(rgb: GLvectorf3, a: SomeInteger|SomeFloat): GLvectorf4 = [rgb[0], rgb[1], rgb[2], a.GLfloat]

template vec2*(v: SomeInteger|SomeFloat): GLvectorf2 = [v.GLfloat, v.GLfloat]
template vec3*(v: SomeInteger|SomeFloat): GLvectorf3 = [v.GLfloat, v.GLfloat, v.GLfloat]
template vec4*(v: SomeInteger|SomeFloat): GLvectorf4 = [v.GLfloat, v.GLfloat, v.GLfloat, v.GLfloat]

template x*(v: GLVector): GLfloat = v[0]
template y*(v: GLVector): GLfloat = v[1]
template z*(v: GLvectorf3 | GLvectorf4): GLfloat = v[2]
template w*(v: GLvectorf3 | GLvectorf4): GLfloat = v[3]
template xy*(v: GLvectorf3): GLvectorf2 = vec2(v[0], v[1])
template xyz*(v: GLvectorf4): GLvectorf3 = vec3(v[0], v[1], v[2])

template r*(v: GLVector): GLfloat = v.x
template g*(v: GLVector): GLfloat = v.y
template b*(v: GLvectorf3 | GLvectorf4): GLfloat = v.z
template a*(v: GLvectorf4): GLfloat = v.w
template rg*(v: GLVector): GLvectorf2 = v.xy
template rgb*(v: GLvectorf3 | GLvectorf4): GLvectorf3 = v.xyz

template `x=`*(v: GLVector, x: GLfloat) = v[0] = x
template `y=`*(v: GLVector, y: GLfloat) = v[1] = y
template `z=`*(v: GLVectorf3 | GLVectorf4, z: GLfloat) = v[2] = z
template `w=`*(v: GLVectorf4, w: GLfloat) = v[3] = w
template `xy=`*(v: GLVector, xy: GLvectorf2) =
  v.x = xy.x
  v.y = xy.y
template `xyz=`*(v: GLVectorf3 | GLVectorf4, xyz: GLvectorf3) =
  v.x = xy.x
  v.y = xy.y
  v.z = xy.z

template `r=`*(v: GLVector, r: GLfloat) = v[0] = r
template `g=`*(v: GLVector, g: GLfloat) = v[1] = g
template `b=`*(v: GLVectorf3 | GLVectorf4, b: GLfloat) = v[2] = b
template `a=`*(v: GLVectorf4, a: GLfloat) = v[3] = a
template `rg=`*(v: GLVector, rg: GLvectorf2) =
  v.r = rg.r
  v.g = rg.g
template `rgb=`*(v: GLVectorf3 | GLVectorf4, rgb: GLvectorf3) =
  v.r = rgb.r
  v.g = rgb.g
  v.b = rgb.b

func brighten*[T: GLvectorf3|GLvectorf4](colour: T, value: GLfloat): T =
  ## Multiply the rgb elements of a colour without changing alpha.
  result[0] = colour[0] * value
  result[1] = colour[1] * value
  result[2] = colour[2] * value
  when colour is GLVectorf4:
    result[3] = colour[3]

func withAlpha*(col: GLvectorf4, alpha: GLfloat): GLvectorf4 =
  vec4(col.r, col.g, col.b, alpha)

func sqrLen*(v: openarray[GLfloat]): GLfloat {.inline.} =
  for i in 0 ..< v.len:
    {.unroll.}
    result += v[i] * v[i]

template length*(v: openarray[GLfloat]): GLfloat = sqrt(v.sqrLen)

proc rotate2d*[T: GLVectorf2 | GLvectorf3](v: var T, angle: GLfloat) =
  ## Sign donates direction
  let
    s = sin(angle)
    c = cos(angle)
    newX = c * v.x - s * v.y
  v.y = c * v.y + s * v.x
  v.x = newX

proc rotated2d*[T: GLVectorf2 | GLvectorf3](v: T, angle: GLfloat): T =
  ## Return a rotated copy of `v`.
  result = v
  result.rotate2d(angle)

proc rotate2d*[T: GLVectorf2 | GLvectorf3](vecs: var openarray[T], angle: GLfloat) =
  for i in 0 ..< vecs.len:
    vecs[i].rotate2d

proc rotated2d*[T: openarray[GLVectorf2 | GLvectorf3]](vecs: T, angle: GLfloat): T =
  when result is seq:
    result.setLen vecs.len
  for i, v in vecs:
    result[i] = v.rotated2d(angle)

macro makeOps*(ty: typedesc[array]): untyped =
  ## Builds `+`, `-`, `*`, `/`, `+=`, `-=`, `*=`, and `/=` operators,
  ## inversion with `-`, and `clamp` for array types.
  ## 
  ## Usage:
  ## 
  ## .. code-block:: nim
  ##    type
  ##      Arr3 = array[3, int]
  ##      Arr4 = array[0..3, int]
  ##    makeOps Arr3
  ##    makeOps Arr4
  ##    assert [1, 2, 3] + [1, 2, 3] + 2 == [4, 6, 8]
  ##    assert [1, 2, 3, 4] - 2 + [1, 2, 3, 4] == [0, 2, 4, 6]
  ## 
  ##    var a: Arr3
  ##    a += 10
  ##    a *= [2, 3, 4]
  ##    a = a.clamp(25, 35)
  ##    assert a == [25, 30, 35]
  ##    assert -a == [-25, -30, -35]

  let
    impl = ty.getImpl
  
  let
    len =
      if impl[2][1].kind == nnkIntLit:
        impl[2][1].intVal - 1
      else:
        impl[2][1].expectKind nnkInfix
        impl[2][1][2].intVal
    sym = impl[2][2]
    rootTypeStr = $(sym.getType())
    a = ident "a"
    b = ident "b"
    ops = 
      if rootTypeStr == "int":
        @["+", "-", "*"]
      else:
        @["+", "-", "*", "/"]

  result = newStmtList()
  for opStr in ops:
    # Each array operation is the same operator (in-place or not) on each element.
    let
      op = nnkAccQuoted.newTree(ident opStr)
      opEq = nnkAccQuoted.newTree(ident opStr & "=")
    var
      opTyTy = nnkBracket.newTree()
      opTyVal = nnkBracket.newTree()
      opValTy = nnkBracket.newTree()
      opEqTy = newStmtList()
      opEqVal = newStmtList()
      
    for i in 0 .. len:
      opTyTy.add(   quote do: `op`(`a`[`i`], `b`[`i`]))
      opTyVal.add(quote do: `op`(`a`[`i`], `b`))
      opValTy.add(quote do: `op`(`a`, `b`[`i`]))
      opEqTy.add(   quote do: `opEq`(`a`[`i`], `b`[`i`]))
      opEqVal.add(quote do: `opEq`(`a`[`i`], `b`))
      
    result.add(quote do:
      func `op`*(`a`, `b`: `ty`): `ty` {.inline,noInit.} = `opTyTy`
      func `op`*(`a`: `ty`, `b`: `sym`): `ty` {.inline,noInit.}  = `opTyVal`
      func `op`*(`a`: `sym`, `b`: `ty`): `ty` {.inline,noInit.}  = `opValTy`
      func `opEq`*(`a`: var `ty`, `b`: `ty`) {.inline,noInit.} = `opEqTy`
      func `opEq`*(`a`: var `ty`, `b`: `sym`) {.inline,noInit.}  = `opEqVal`
    )

  proc genInfixes(clauses: seq[NimNode], connector: string): NimNode =
    var parent = newEmptyNode()
    for c in clauses:
      if parent.kind == nnkEmpty: parent = c
      else: parent = infix(parent, connector, c)
    parent
    
  # Inversion, clamp, and '<=' operator.
  # Defining '<=' allows '>=' and permits use of 'min' and 'max'.
  var
    opInv = nnkBracket.newTree()
    opAbs = nnkBracket.newTree()
    opClamp = nnkBracket.newTree()
    opLEConds: seq[NimNode]
  
  let
    v = ident "v"
  
  for i in 0 .. len:
    opInv.add(    quote do: -`a`[`i`])
    opAbs.add(    quote do: abs(`a`[`i`]))
    opClamp.add(  quote do: clamp(`v`[`i`], `a`, `b`) )
    opLEConds.add(quote do: `a`[`i`] <= `b`[`i`])
  
  let
    invOp = nnkAccQuoted.newTree(ident "-")
    absOp = ident "abs"
    lessEq = nnkAccQuoted.newTree(ident "<=")
    opLE = opLEConds.genInfixes "and"
    clampOp = ident "clamp"
  
  result.add(quote do:
    func `invOp`*(`a`: `ty`): `ty` = `opInv`
    func `absOp`*(`a`: `ty`): `ty` = `opAbs`
    func `clampOp`*(`v`: `ty`, `a`, `b`: `sym`): `ty` {.inline,noInit.} = `opClamp`
    func `lessEq`*(`a`, `b`: `ty`): bool {.inline,noInit.}  = `opLE`
  )

makeOps GLvectorf2
makeOps GLvectorf3
makeOps GLvectorf4

func dot*(v1, v2: GLvector): GLfloat =
  ## Calculate the dot product of two vectors.
  assert v1.len == v2.len, "Vectors must be the same length"
  for i, v in v1:
    {.unroll.}
    result = result + v * v2[i]

func cross*(v1, v2: GLvectorf3): GLvectorf3 =
  ## Calculate the cross product of two vectors
  [
    v1.y * v2.z - v1.z * v2.y,
    v1.z * v2.x - v1.x * v2.z,
    v1.x * v2.y - v1.y * v2.x
  ]

func reflect*(incident, normal: GLvectorf2): GLvectorf2 =
  let d = 2.0 * dot(normal, incident)
  result = vec2(incident[0] - d * normal[0], incident[1] - d * normal[1])

#------------------------------------------------------------------------------------
# Mix and step support: Linear & Hermite interpolation over GLfloat values and arrays
#------------------------------------------------------------------------------------

template mix*(x, y, a: float|GLfloat): float =
  ## Mix two floats according to `a`.
  x * (1.0 - a) + y * a

template assertNormalised*(a: GLfloat) =
  assert a in 0.0..1.0, "Value out of range: got " & $a & ", expected 0..1"

template assertNormalised*(v: GLVector) =
  for item in v:
    item.assertNormalised

func mix*[N: static[int], T: array[N, GLfloat]](v1, v2: T, a: GLfloat): T {.inline.} =
  ## Mix two arrays of floats together according to `a`.
  a.assertNormalised()
  for i in 0 ..< N:
    result[i] = v1[i] * (1.0 - a) + v2[i] * a

func mixSelect*[N: static[int], T: array[N, GLfloat]](items: openarray[T], a: float): T =
  ## Interpolate a list of vectors with a normalised `a`.
  ## Neighbouring values are mixed together by how close their index
  ## is to `a`.
  a.assertNormalised()
  let
    i1 = int(a * items.high.float)
    i2 = min(items.high, i1 + 1)
    fracPerItem = 1.0 / items.high.float
    valueIntoItem = a mod fracPerItem
    normIntoItem = valueIntoItem / fracPerItem
  items[i1].mix(items[i2], normIntoItem)

func select*[N: static[int], T: array[N, GLfloat]](items: openarray[T], a: float): T =
  ## Select a vector using a normalised index.
  assert items.len > 0, "No items to select from"
  items[clamp(int(a * float(items.high)), 0, items.high)]

func smoothStep*[T: Somefloat](x, y, a: T): T {.inline.} =
  ## Smooth Hermite interpolation between two values.
  a.assertNormalised()
  let t = a * a * (3.0 - 2.0 * a)
  mix(x, y, t)
  
func smootherStep*[T: Somefloat](x, y, a: T): T {.inline.} =
  ## Slightly smoother at the edges in interpolation than smoothStep.
  a.assertNormalised()
  let t = a * a * a * (a * (6.0 * a - 15.0) + 10.0)
  mix(x, y, t)

#--------
# Normals
#--------

func normal*[T: GLVector](a: T): T {.inline, noInit.} =
  ## Calculate the normal of a vector.
  let mag = a.length
  if mag > 0:
    for i in 0 .. a.high:
      {.unroll.}
      result[i] = a[i] / mag
  else:
    result[0] = 1.0
    result[1] = 0.0

proc triangleNormal*(v1, v2, v3: GLVectorf3): GLvectorf3 =
  ## Calculates the surface normal of the triangle made by the three vertices
  ## by taking the vector cross product of the two edges.
  ## See: https://www.khronos.org/opengl/wiki/Calculating_a_Surface_Normal
  ## Note: The order of the vertices used in the calculation will affect the direction of the normal (in or out of the face w.r.t. winding).
  let
    u = v2 - v1
    v = v3 - v1
  result[0] = u.y * v.z - u.z * v.y
  result[1] = u.z * v.x - u.x * v.z
  result[2] = u.x * v.y - u.y * v.x

proc triangleNormals*(vertices: openarray[GLvectorf3]): seq[GLvectorf3] =
  ## Calculate the surface normals for the given triangles.
  result = newSeq[GLvectorf3](vertices.len)

  assert(vertices.len mod 3 == 0, "Vertex count must be a multiple of three")
  var triNorms = newSeq[GLvectorf3](vertices.len div 3)

  var p: int
  for i in 0 ..< vertices.len div 3:
    p = i * 3
    triNorms[i] = triangleNormal(vertices[p], vertices[p + 1], vertices[p + 2])

  # We now want to sum and average surrounding face normals to get the vertex normals.
  var tris: int
  for i in 0 ..< vertices.len:
    result[i] = triNorms[i div 3]
    tris = 1
    for adjIdx in 0 ..< vertices.len:
      let dist = length(vertices[adjIdx] - vertices[i])
      if adjIdx != i and dist < 0.001:
        result[i] += triNorms[adjIdx div 3]
        tris += 1
    if tris > 1:
      result[i] = result[i] / tris.float
    result[i] = result[i].normal 

#-----------
# Misc utils
#-----------

func constrain*(v: var GLVector, maxLength: SomeFloat) =
  ## Vector cannot go over maxLength but retains angle.
  let
    sLen = v.sqrLen
    sLim = maxLength * maxLength
  if sLen > sLim:
    let
      vLen =  sqrt(sLen)
      nx = v.x / vLen
      ny = v.y / vLen
    v.x = maxLength * nx
    v.y = maxLength * ny

proc constrain*[T: GLVector](v: T, maxLength: SomeFloat): T {.noInit.} =
  result = v
  result.constrain(maxLength)

func setLength*(v: var GLVector, length: float | GLfloat) =
  ## Vector is set to `length` but retains angle.
  let vLen =  v.length
  if vLen == 0.0: return
  let
    c = v.x / vLen
    s = v.y / vLen
  v.x = length * c
  v.y = length * s

proc asLength*[T: GLVector](v: T, length: float | GLfloat): T {.noInit} =
  result = v
  result.setLength length

func rotate90L*(original: GLVectorf2): GLVectorf2 = vec2(original[1], -original[0])
func rotate90R*(original: GLVectorf2): GLVectorf2 = vec2(-original[1], original[0])

template vector*(angle: float, length = 1.0): GLvectorf2 =
  [(length * cos(angle)).GLfloat, length * sin(angle)]

proc toAngle*(vec: GLVectorf2): float = arcTan2 vec.y, vec.x

func angleDiffAbs*(a, b: float): float =
  ## Compare two angles and return the absolute difference.
  ## Angles must be within 0..TAU.
  PI - abs(abs(a - b) - PI)

func angleDiff*(a, b: float): float =
  ## Compare two angles and return the signed difference.
  ## Angles must be within 0..TAU.
  result = (a - b) + PI
  result = result / TAU
  result = ((result - floor(result)) * TAU) - PI

func taxiCabAngle*(x, y: float): float {.inline.} =
  ## Returns the angle based on rectilinear distance.
  ## The result ranges from 0.0 .. 4.0.
  if y >= 0:
    if x >= 0:
      y / (x + y)
    else:
      1 - x / (-x + y)
  else:
    if x < 0:
      2 - y / (-x - y)
    else:
      3 + x / (x - y)


# --------
# Matrices
# --------

template mat4*(v: SomeInteger|SomeFloat): GLmatrixf4 = [
  vec4(v.GLfloat, 0.0, 0.0, 0.0),
  vec4(0.0, v.GLfloat, 0.0, 0.0),
  vec4(0.0, 0.0, v.GLfloat, 0.0),
  vec4(0.0, 0.0, 0.0, v.GLfloat)
]

template mat4*(a, b, c, d: GLvectorf4): GLmatrixf4 = [a, b, c, d]

func identity*[N: static[int]]: array[N, array[N, GLfloat]] =
  ## Example: `echo identity[3]()`.
  for i in 0 ..< N:
    {.unroll.}
    result[i][i] = 1.0'f32

proc `$`*[N: static[int]](m: array[N, array[N, GLfloat]]): string =
  for r in m:
    result &= $r & "\n"

func `+`*(m1, m2: GLmatrixf4): GLmatrixf4 {.inline, noInit.} =
  for r in 0 .. 3:
    {.unroll.}
    for c in 0 .. 3:
      {.unroll.}
      result[r][c] = m1[r][c] + m2[r][c]

func `-`*(m1, m2: GLmatrixf4): GLmatrixf4 {.inline, noInit.} =
  for r in 0 .. 3:
    {.unroll.}
    for c in 0 .. 3:
      {.unroll.}
      result[r][c] = m1[r][c] - m2[r][c]

func `*`*[R, C, X: static[int]](
    m: array[0 .. R, array[0 .. C, GLfloat]],
    v: array[0 .. X, GLfloat]): array[0 .. X, GLfloat] {.inline, noInit.} =
  ## Multiply two matrices.
  ## 
  ## The number of columns in `m1` must equal the number of rows in `m2`.
  for r in 0 .. R:
    {.unroll.}
    for c1 in 0 .. X:
      {.unroll.}
      for c2 in 0 .. C:
        {.unroll.}
        result[c1] += m[r][c2] * v[c1]

func `*`*[R, C, X: static[int]](
    m1: array[R, array[C, GLfloat]],
    m2: array[C, array[X, GLfloat]]): array[R, array[X, GLfloat]] {.inline, noInit.} =
  ## Multiply two matrices.
  ## 
  ## The number of columns in `m1` must equal the number of rows in `m2`.
  for r in 0 ..< R:
    {.unroll.}
    for c1 in 0 ..< C:
      {.unroll.}
      for c2 in 0 ..< X:
        {.unroll.}
        result[r][c1] += m1[r][c2] * m2[c2][c1]

func scale*(m: GLmatrixf4, value: GLfloat): GLmatrixf4 {.inline, noInit.} =
  result = m
  for i in 0 .. 3:
    result[i][i] *= value

func scale*(m: var GLmatrixf4, value: GLfloat) {.inline, noInit.} =
  for i in 0 .. 3:
    m[i][i] *= value

func translationMatrixC*(offset: GLvectorf3): GLmatrixf4 =
  ## Return a column-major translation matrix.
  [
    [1'f32, 0, 0, offset[0]],
    [0'f32, 1, 0, offset[1]],
    [0'f32, 0, 1, offset[2]],
    [0'f32, 0, 0, 1],
  ]

func translationMatrixR*(offset: GLvectorf3): GLmatrixf4 =
  ## Return a row-major translation matrix.
  [
    [1'f32, 0, 0, 0],
    [0'f32, 1, 0, 0],
    [0'f32, 0, 1, 0],
    [offset[0], offset[1], offset[2], 1],
  ]

template translate*(m: var GLmatrixf4, position: GLvectorf3) =
  m[2][0] = position[0]
  m[2][1] = position[1]
  m[2][2] = position[2]

template translate*(m: var GLmatrixf4, positionXY: GLvectorf2) =
  m[2][0] = positionXY[0]
  m[2][1] = positionXY[1]

func rotateX*(m: var GLmatrixf4, angle: GLfloat) =
  let
    c = cos angle
    s = sin angle
  m[1][1] = c
  m[1][2] = -s
  m[2][1] = s
  m[2][2] = c

func rotateY*(m: var GLmatrixf4, angle: GLfloat) =
  let
    c = cos angle
    s = sin angle
  m[0][0] = c
  m[0][2] = s
  m[2][0] = -s
  m[2][2] = c

func rotateZ*(m: var GLmatrixf4, angle: GLfloat) =
  let
    c = cos angle
    s = sin angle
  m[0][0] = c
  m[0][1] = -s
  m[1][0] = s
  m[1][1] = c

func perspectiveMatrix*(fovY, aspect, zNear, zFar: GLfloat): GLmatrixf4 {.noInit.} =
  ## Return a perspective matrix.
  assert aspect != 0.0'f32
  assert zFar != zNear
  const
    one = 1.0'f32
    two = 2.0'f32
  let
    hTanFov = tan(fovY * 0.5).GLfloat
    xScale = one / (aspect * hTanFov)
    yScale = one / hTanFov
    zDist = zFar - zNear

  [
    [xScale, 0, 0, 0],
    [0'f32, yScale, 0, 0],
    [0'f32, 0, -((zFar + zNear) / zDist), -((two * zFar * zNear) / zDist)],
    [0'f32, 0, -one, 0.0]
  ]  

func viewMatrix*(eye, target: GLvectorf3, up = vec3(0.0, 1.0, 0.0)): GLmatrixf4 {.inline.} =
  ## Return a view matrix to define world coordinates.
  ## 
  ## The default value for `up` defines a right-handed coordinate mapping.
  var
    zAxis = normal(target - eye)
  let
    xAxis = normal(cross(zAxis, up))
    yAxis = cross(xAxis, zAxis)

  zAxis = -zAxis

  [
    vec4(xAxis.x, xAxis.y, xAxis.z, -dot(xAxis, eye)),
    vec4(yAxis.x, yAxis.y, yAxis.z, -dot(yAxis, eye)),
    vec4(zAxis.x, zAxis.y, zAxis.z, -dot(zAxis, eye)),
    vec4(0, 0, 0, 1)
  ]

template lookAt*(m: var GLmatrixf4, eye, target: GLvectorf3, up = vec3(0.0, 1.0, 0.0)) =
  ## Alias for `viewMatrix`.
  m = viewMatrix(eye, target, up)


#-------------------------------
# Line traversal / interpolation
#-------------------------------


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
  ## Start and end points are both included in the interpolation.
  block:
    let
      inclSteps = steps - 1
      dist = vec2(x2 - x1, y2 - y1)
      stepX {.inject.} = dist[0] / inclSteps.float
      stepY {.inject.} = dist[1] / inclSteps.float
      maxHVar = variance / 2
      midI = inclSteps div 2
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
      normal = vec2(-dy, dx).normal
      lastOffset, r: float

    # generate line points
    for i in 0 .. inclSteps:
      if i < midI:
        iDist = midI - i
      else:
        iDist = i - midI
      hVar = (1 - (iDist.float / inclSteps.float)) * variance
      lineXCoord += stepX
      lineYCoord += stepY
      r = rand(-0.01..0.01)
      curOffset += r
      curOffset = clamp(curOffset, -hVar, hVar)
      lineIdx = i

      actions
      lastOffset = curOffset

      xCoord = lineXCoord + normal[0] * curOffset
      yCoord = lineYCoord + normal[1] * curOffset

when isMainModule:
  import unittest

  type
    Arr3 = array[3, int]
    Arr4 = array[0..3, int]
  makeOps Arr3
  makeOps Arr4

  suite "Utilities":
    test "makeOps":
      check [1, 2, 3] + [1, 2, 3] + 2 == [4, 6, 8]
      check [1, 2, 3, 4] - 2 + [1, 2, 3, 4] == [0, 2, 4, 6]
      var a: Arr3
      a += 10
      a *= [2, 3, 4]
      a = a.clamp(25, 35)
      check a == [25, 30, 35]
      check -a == [-25, -30, -35]
      check max([1, 4, 3], [3, 4, 5]) == [3, 4, 5]
      check min([1, 4, 3], [3, 4, 5]) == [1, 4, 3]
    test "Matrices":
      let
        m1 = mat4(vec4(1, 2, 3, 4), vec4(5, 6, 7, 8), vec4(9, 10, 11, 12), vec4(13, 14, 15, 16))
        m2 = mat4(vec4(2, 3, 4, 5), vec4(6, 7, 8, 9), vec4(10, 11, 12, 13), vec4(14, 15, 16, 17))
      
      check (m1 + m2) == mat4(
        vec4(3, 5, 7, 9),
        vec4(11, 13, 15, 17),
        vec4(19, 21, 23, 25),
        vec4(27, 29, 31, 33)
      )
      check (m1 - m2) == mat4(
        vec4(-1, -1, -1, -1),
        vec4(-1, -1, -1, -1),
        vec4(-1, -1, -1, -1),
        vec4(-1, -1, -1, -1),
      )
      check (m1 * m2) == mat4(
        vec4(100, 110, 120, 130),
        vec4(228, 254, 280, 306),
        vec4(356, 398, 440, 482),
        vec4(484, 542, 600, 658)
      )

