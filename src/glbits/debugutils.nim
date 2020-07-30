when defined(debugGL):
  import os

proc debugMsg*(s: string) =
  ## Report the string `s` along with the line number and proc it was invoked outside of glbits.
  when defined(debugGL):
    let entries = getStackTraceEntries()
    const sourceDir = currentSourcePath().parentDir

    # Find first stack line outside of the current source directory.
    var stackIdx: int
    for idx in countDown(entries.high, 0):
      let
        fn = $entries[idx].filename
        dir = fn.parentDir
      if dir != sourceDir:
        stackIdx = idx
        break
    let
      st = entries[stackIdx]
      fnStr = $(st.filename)
      fn = fnStr.extractFilename 
      debugPrefix = "GLBits [" & fn & " " & $st.procname & " line: " & $st.line & "] "
    echo debugPrefix & s
