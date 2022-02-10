
# ---------------
# Processing GLSL
# ---------------

from strutils import split, find, strip
from streams import newFileStream, readLine, close
from os import splitPath, joinPath
import macros


proc readAndInclude*(filePath: string, announce = true, includeStr = "//## include", ext = ".glsl", echoOutput = false): string =
  ## Reads the file at `filePath` and replaces occurrences of `includeStr`
  ## with the contents of files passed to it from the relative path.
  ## 
  ## File paths after `includeStr` are comma separated, and can use `..`
  ## for previous directory and `[]` for multiple files from a path.
  ## 
  ## Parameters:
  ## 
  ##  - `filePath`: absolute path of file to process.
  ##  - `announce`: when true this will `echo` which files have been included for `filePath`.
  ##  - `includeStr`: this string defines the marker to search for to include files.
  ##  - `ext`: the file extension to postfix to included filenames.
  ##  - `echoOutput`: when true this will `echo` the final `string`.
  ## 
  ## Example:
  ## 
  ##    // myShader GLSL.
  ##    //## include mysetup, /../lib/[interpolate, hash, noise]
  ##    myOutput = noise(myCoord);
  ##    
  ##    ## Nim file.
  ##    const thisDir = currentSourcePath().parentDir
  ##    let
  ##      shaderText =
  ##        readAndInclude(
  ##          thisDir.joinPath r"\shaders\fragment\myShader.glsl",
  ##          echoOutput = true
  ##        )
  ## 

  let
    impStrLen = includeStr.len
    fileDir = filePath.splitPath.head

  if announce: echo "GLSL read & include for '", filePath, "'"

  var
    stream = newFileStream(filePath, fmRead)
    line: string
    res: string

  if not stream.isNil:
    while stream.readLine(line):
      let found = find(line, includeStr)
      if found > -1:
        var
          toInclude: seq[string]
          lastPath: string
          bracketOpen: bool
          filePath: string

        # Separate arguments and expand paths in brackets.
        for inclPathLit in line[impStrLen .. ^1].split(','):
          var inclPath = inclPathLit.strip
          let bracket1 = inclPath.find "["
          
          if not bracketOpen:
            # Prefix this and subsequent paths.
            if bracket1 > -1:
              bracketOpen = true
              let dir = inclPath[0 ..< bracket1]
              inclPath = inclPath[bracket1 + 1.. ^1]
              lastPath = fileDir.joinPath(dir)
          else:
            doAssert bracket1 < 0, "Cannot embed multiple brackets"

          let bracket2 = inclPath.find ']'

          if bracketOpen:
            if bracket2 > -1:
              # Last bracket item.
              bracketOpen = false
              filePath = lastPath.joinPath(inclPath[0 ..^ 2]) & ext
            else:
              filePath = lastPath.joinPath(inclPath) & ext
          else:
            doAssert bracket2 < 0, "Found closing ']' with no opening '['"
            filePath = fileDir.joinPath(inclPath) & ext
          
          if announce: echo "  Including: ", filePath
          res &= readFile(filePath) & "\n"

        doAssert not bracketOpen, "Cannot find closing ']' in '" & line & "'"
      else:
        res &= line & "\n"

    stream.close()
  else:
    doAssert false, "GLSL include cannot find '" & filePath & "'"

  if echoOutput:
    echo res
  res
