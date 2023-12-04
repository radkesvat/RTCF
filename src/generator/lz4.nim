when defined(useFuthark) or defined(useFutharkForExample):
  import futhark, os
  const OUTPUT_DIR {.strdefine.} = ""
  const ROOT_DIR {.strdefine.} = ""
  static:
    echo ROOT_DIR
    echo OUTPUT_DIR
  importc:
    outputPath OUTPUT_DIR / "lz4.nim"
    path ROOT_DIR / "libs" / "lz4" / "lib"
    "lz4frame_static.h"

else:
  include "generated.nim"