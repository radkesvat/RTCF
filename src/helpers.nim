#shared to all other modules, provides log and some constants
import chronicles,strformat

export chronicles,strformat

const hasThreadSupport* = compileOption("threads")

# reason: stringview implentation
static: doAssert NimMajor >= 2 , "Not supporting Nim < 2 !"

# publicLogScope:
