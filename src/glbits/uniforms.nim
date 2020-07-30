import opengl, glbits, modelrenderer, strformat, debugutils

proc getUniformLocation*(program: GLuint, name: string, allowMissing = false): Uniform = 
  let uni = glGetUniformLocation(program, name)
  if not allowMissing and uni < 0:
    raise newException(ValueError, &"getLocation: Cannot find uniform name '{name} ({uni})'")
  else:
    return uni.Uniform 

proc getUniformLocation*(program: ShaderProgramId | ShaderProgram, name: string, allowMissing = false): Uniform =
  getUniformLocation(program.id, name, allowMissing)

# Direct setters

proc setInt1*(uniform: Uniform, value: GLInt) =
  uniform.GLint.glUniform1i value
  debugMsg &"Set [uniform {uniform.name}] to {value}"
template setInt*(uniform: Uniform, value: GLInt) = uniform.setInt1 value.GLInt
proc setInt2*(uniform: Uniform, value1, value2: GLInt) =
  uniform.GLint.glUniform2i value1, value2
  debugMsg &"Set [uniform {uniform.name}] to {value1}, {value2}"
proc setInt3*(uniform: Uniform, value1, value2, value3: GLInt) =
  uniform.GLint.glUniform3i value1, value2, value3
  debugMsg &"Set [uniform {uniform.name}] to {value1}, {value2}, {value3}"
proc setInt4*(uniform: Uniform, value1, value2, value3, value4: GLInt) =
  uniform.GLint.glUniform4i value1, value2, value3, value4
  debugMsg &"Set [uniform {uniform.name}] to {value1}, {value2}, {value3}, {value4}"

template setUInt1*(uniform: Uniform, value: GLuint): untyped = uniform.GLint.glUniform1ui value
template setUInt*(uniform: Uniform, value: GLInt): untyped = uniform.setUInt1 value.GLUInt
template setUInt2*(uniform: Uniform, value1, value2: GLuint): untyped = uniform.GLint.glUniform2ui value1, value2
template setUInt3*(uniform: Uniform, value1, value2, value3: GLuint): untyped = uniform.GLint.glUniform3ui value1, value2, value3
template setUInt4*(uniform: Uniform, value1, value2, value3, value4: GLuint): untyped = uniform.GLint.glUniform4ui value1, value2, value3, value4

proc setFloat1*(uniform: Uniform, value: GLFloat) =
  uniform.GLint.glUniform1f value
  debugMsg &"Set [uniform {uniform.int}] to {value}"
template setFloat*(uniform: Uniform, value: GLFloat) = uniform.setFloat1 value
proc setFloat2*(uniform: Uniform, value1, value2: GLFloat) =
  uniform.GLint.glUniform2f value1, value2
  debugMsg &"Set [uniform {uniform.int}] to {value1}, {value2}"
proc setFloat3*(uniform: Uniform, value1, value2, value3: GLFloat) =
  uniform.GLint.glUniform3f value1, value2, value3
  debugMsg &"Set [uniform {uniform.int}] to {value1}, {value2}, {value3}"
proc setFloat4*(uniform: Uniform, value1, value2, value3, value4: GLFloat) =
  uniform.GLint.glUniform4f value1, value2, value3, value4
  debugMsg &"Set [uniform {uniform.int}] to {value1}, {value2}, {value3}, {value4}"

# Vector uniform setter assists

template setVec2*(uniform: Uniform, value: GLvectorf2): untyped =
  uniform.setFloat2(value[0], value[1])

template setVec*(uniform: Uniform, value: GLvectorf2): untyped =
  uniform.setVec2(value)

template setVec3*(uniform: Uniform, value: GLvectorf3): untyped =
  uniform.setFloat3(value[0], value[1], value[2])

template setVec4*(uniform: Uniform, value: GLvectorf4): untyped =
  uniform.setFloat4(value[0], value[1], value[2], value[4])

# Indirect setters
# Use these to update uniform arrays with set values

template setInt*(uniform: Uniform, count: Natural, value: ptr GLInt): untyped =
  uniform.GLint.glUniform1iv(count.GLsizei, value)
  debugMsg &"Set [uniform {uniform.int}] with {count} values"

template setUInt*(uniform: Uniform, count: Natural, value: ptr GLUInt): untyped =
  uniform.GLint.glUniform1uiv(count.GLsizei, value)
  debugMsg &"Set [uniform {uniform.int}] with {count} values"

template setFloat*(uniform: Uniform, count: Natural, value: ptr GLFloat): untyped =
  uniform.GLint.glUniform1ufv(count.GLsizei, value)
  debugMsg &"Set [uniform {uniform.int}] with {count} values"



