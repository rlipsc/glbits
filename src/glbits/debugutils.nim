when defined(debugGL):
  import os, macros, strutils

proc debugMsg*(s: string) =
  ## Report the string `s` along with the line number and proc it was invoked outside of glbits.
  when defined(debugGL):
    let entries = getStackTraceEntries()
    const sourceDir = currentSourcePath().parentDir

    var li: string
    if entries.len > 0:
      # Find first stack line outside of the glbits source directory.
      var
        stackIdx = entries.high
        found: bool
      
      for idx in countDown(entries.high, 0):
        let
          fn = $entries[idx].filename
          dir = fn.parentDir
        
        if sourceDir notin dir:
          found = true
          stackIdx = idx
          break
     
      let
        st = entries[stackIdx]
        fnStr = $(st.filename)
        fn = fnStr.extractFilename 
      li = $LineInfo(filename: fnStr, line: st.line, column: 0)

    let
      padLen = 85
      pad = if s.len > padLen: "" else: " ".repeat(padLen - s.len)

    echo "GLBits " & s & " " & $pad & " " & $li
