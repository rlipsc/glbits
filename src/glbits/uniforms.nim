import opengl, glbits, modelrenderer, strformat

# Uniforms
type Uniform* = GLint

proc getUniformLocation*(program: GLuint, name: string, allowMissing = false): Uniform = 
  let uni = glGetUniformLocation(program, name)
  if not allowMissing and uni < 0:
    raise newException(ValueError, &"getLocation: Cannot find uniform name '{name} ({uni})'")
  else:
    echo &"Uniform location: {name} = {uni}"
    return uni.Uniform 

proc getUniformLocation*(program: ShaderProgram, name: string, allowMissing = false): Uniform =
  getUniformLocation(program.id, name, allowMissing)

proc getUniformLocation*(program: ShaderProgramId, name: string, allowMissing = false): Uniform =
  getUniformLocation(program.shaderProgram, name, allowMissing)

# Direct setters

template setInt1*(uniform: Uniform, value: GLInt): untyped = uniform.GLint.glUniform1i value
template setInt*(uniform: Uniform, value: GLInt): untyped = uniform.setInt1 value.GLInt
template setInt2*(uniform: Uniform, value1, value2: GLInt): untyped = uniform.GLint.glUniform2i value1, value2
template setInt3*(uniform: Uniform, value1, value2, value3: GLInt): untyped = uniform.GLint.glUniform3i value1, value2, value3
template setInt4*(uniform: Uniform, value1, value2, value3, value4: GLInt): untyped = uniform.GLint.glUniform4i value1, value2, value3, value4

template setUInt1*(uniform: Uniform, value: GLuint): untyped = uniform.GLint.glUniform1ui value
template setUInt*(uniform: Uniform, value: GLInt): untyped = uniform.setUInt1 value.GLUInt
template setUInt2*(uniform: Uniform, value1, value2: GLuint): untyped = uniform.GLint.glUniform2ui value1, value2
template setUInt3*(uniform: Uniform, value1, value2, value3: GLuint): untyped = uniform.GLint.glUniform3ui value1, value2, value3
template setUInt4*(uniform: Uniform, value1, value2, value3, value4: GLuint): untyped = uniform.GLint.glUniform4ui value1, value2, value3, value4

template setFloat1*(uniform: Uniform, value: GLFloat): untyped = uniform.GLint.glUniform1f value
template setFloat*(uniform: Uniform, value: GLFloat): untyped = uniform.setFloat1 value
template setFloat2*(uniform: Uniform, value1, value2: GLFloat): untyped = uniform.GLint.glUniform2f value1, value2
template setFloat3*(uniform: Uniform, value1, value2, value3: GLFloat): untyped = uniform.GLint.glUniform3f value1, value2, value3
template setFloat4*(uniform: Uniform, value1, value2, value3, value4: GLFloat): untyped = uniform.GLint.glUniform4f value1, value2, value3, value4

# Vector uniform setter assists

template setVec*(uniform: Uniform, value: GLvectorf2): untyped =
  uniform.setFloat2(value[0], value[1])

# Indirect setters
# Use these to update uniform arrays with set values

template setInt*(uniform: Uniform, count: Natural, value: ptr GLInt): untyped = uniform.GLint.glUniform1iv(count.GLsizei, value)
template setUInt*(uniform: Uniform, count: Natural, value: ptr GLUInt): untyped = uniform.GLint.glUniform1uiv(count.GLsizei, value)
template setFloat*(uniform: Uniform, count: Natural, value: ptr GLFloat): untyped = uniform.GLint.glUniform1ufv(count.GLsizei, value)



