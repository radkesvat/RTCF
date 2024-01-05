#shared to all other modules, provides log and some constants
{.used.}

import chronicles,strformat,pretty

export chronicles,strformat,pretty


const hasThreadSupport* = compileOption("threads")

# reason: stringview implementation
static: doAssert NimMajor >= 2 , "Not supporting Nim < 2 !"

# publicLogScope:
