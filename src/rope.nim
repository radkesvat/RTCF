#
#
#            Nim's Runtime Library
#        (c) Copyright 2010 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#           fucked up by Radkesvat


## This module contains support for a `rope`:idx: data type.
## Ropes can represent very long strings efficiently; in particular, concatenation
## is done in O(1) instead of O(n). They are essentially concatenation
## trees that are only flattened when converting to a native Nim
## string. The empty string is represented by `nil`. Ropes are immutable and
## subtrees can be shared without copying.
## Leaves can be cached for better memory efficiency at the cost of
## runtime efficiency.

include system/inclrtl
import streams

when defined(nimPreviewSlimSystem):
  import std/[syncio, formatfloat, assertions]

{.push debugger: off.} # the user does not want to trace a part
                       # of the standard library!



type
  Rope* {.acyclic.} = ref object
    ## A rope data type. The empty rope is represented by `nil`.
    left, right: Rope
    length: int
    data: ptr UncheckedArray[char] # not empty if a leaf

# Note that the left and right pointers are not needed for leafs.
# Leaves have relatively high memory overhead (~30 bytes on a 32
# bit machine) and we produce many of them. This is why we cache and
# share leafs across different rope trees.
# To cache them they are inserted in another tree, a splay tree for best
# performance. But for the caching tree we use the leaf's left and right
# pointers.
# template data(r:Rope): string= r.dataref[]
  
proc len*(a: Rope): int {.rtl, extern: "nro$1".} =
  ## The rope's length.
  if a == nil: 0 else: a.length

proc newRope(): Rope = new(result)

proc newRope(address:pointer,len:int): Rope =
  new(result)
  result.length = len
  result.data = cast[ptr UncheckedArray[char]](address)

template rope*(address:pointer,len:int): Rope = newRope(address,len)


proc `&`*(a, b: Rope): Rope {.rtl, extern: "nroConcRopeRope".} =
  ## The concatenation operator for ropes.
  runnableExamples:
    let r = rope("Hello, ") & rope("Nim!")
    doAssert $r == "Hello, Nim!"

  if a == nil:
    result = b
  elif b == nil:
    result = a
  else:
    result = newRope()
    result.length = a.length + b.length
    result.left = a
    result.right = b

proc `&`*(a: openArray[Rope]): Rope {.rtl, extern: "nroConcOpenArray".} =
  ## The concatenation operator for an `openArray` of ropes.
  runnableExamples:
    let r = &[rope("Hello, "), rope("Nim"), rope("!")]
    doAssert $r == "Hello, Nim!"

  for item in a: result = result & item

proc add*(a: var Rope, b: Rope) {.rtl, extern: "nro$1Rope".} =
  ## Adds `b` to the rope `a`.
  runnableExamples:
    var r = rope("Hello, ")
    r.add(rope("Nim!"))
    doAssert $r == "Hello, Nim!"

  a = a & b

proc `[]`*(r: Rope, i: int): char {.rtl, extern: "nroCharAt".} =
  ## Returns the character at position `i` in the rope `r`. This is quite
  ## expensive! Worst-case: O(n). If `i >= r.len or i < 0`, `\0` is returned.
  runnableExamples:
    let r = rope("Hello, Nim!")

    doAssert r[0] == 'H'
    doAssert r[7] == 'N'
    doAssert r[22] == '\0'

  var x = r
  var j = i
  if x == nil or i < 0 or i >= r.len: return
  while true:
    if x != nil and x.len > 0:
      # leaf
      return x.data[j]
    else:
      if x.left.length > j:
        x = x.left
      else:
        dec(j, x.left.length)
        x = x.right

proc rope*(s: var string): Rope {.rtl, extern: "nro$1Str".} =
  ## Converts a string to a rope.
  runnableExamples:
    let r = rope("I'm a rope")
    doAssert $r == "I'm a rope"

  if s.len == 0:
    result = nil
  else:
    result = newRope(addr s[0],s.len)

iterator leaves*(r: Rope): tuple[buf:ptr UncheckedArray[char],len:int] =
  ## Iterates over any leaf string in the rope `r`.
  runnableExamples:
    let r = rope("Hello") & rope(", Nim!")
    let s = ["Hello", ", Nim!"]
    var index = 0
    for leave in r.leaves:
      doAssert leave == s[index]
      inc(index)

  if r != nil:
    var stack = @[r]
    while stack.len > 0:
      var it = stack.pop
      while it.left != nil:
        assert(it.right != nil)
        stack.add(it.right)
        it = it.left
        assert(it != nil)
      yield (it.data,it.len)

iterator items*(r: Rope): char =
  ## Iterates over any character in the rope `r`.
  for b,l in leaves(r):
    for i in 0..<l: yield b[i]

    # for c in items(s): yield c

# proc write*(f: File, r: Rope) {.rtl, extern: "nro$1".} =
#   ## Writes a rope to a file.
#   for s in leaves(r): write(f, s)

# proc write*(s: Stream, r: Rope) {.rtl, extern: "nroWriteStream".} =
#   ## Writes a rope to a stream.
#   for rs in leaves(r): write(s, rs)

proc `$`*(r: Rope): string {.rtl, extern: "nroToString".} =
  ## Converts a rope back to a string.
  result = newStringOfCap(r.len)
  result.setLen r.len

  var last = 0
  for b,l in leaves(r):
    copyMem(addr result[last],b,l)
    last += l
    # add(result, toOpenArray(b,0,l))

# proc `%`*(frmt: string, args: openArray[Rope]): Rope {.rtl, extern: "nroFormat".} =
#   ## `%` substitution operator for ropes. Does not support the `$identifier`
#   ## nor `${identifier}` notations.
#   runnableExamples:
#     let r1 = "$1 $2 $3" % [rope("Nim"), rope("is"), rope("a great language")]
#     doAssert $r1 == "Nim is a great language"

#     let r2 = "$# $# $#" % [rope("Nim"), rope("is"), rope("a great language")]
#     doAssert $r2 == "Nim is a great language"

#     let r3 = "${1} ${2} ${3}" % [rope("Nim"), rope("is"), rope("a great language")]
#     doAssert $r3 == "Nim is a great language"

#   var i = 0
#   var length = len(frmt)
#   result = nil
#   var num = 0
#   while i < length:
#     if frmt[i] == '$':
#       inc(i)
#       case frmt[i]
#       of '$':
#         add(result, "$")
#         inc(i)
#       of '#':
#         inc(i)
#         add(result, args[num])
#         inc(num)
#       of '0'..'9':
#         var j = 0
#         while true:
#           j = j * 10 + ord(frmt[i]) - ord('0')
#           inc(i)
#           if i >= frmt.len or frmt[i] notin {'0'..'9'}: break
#         add(result, args[j-1])
#       of '{':
#         inc(i)
#         var j = 0
#         while frmt[i] in {'0'..'9'}:
#           j = j * 10 + ord(frmt[i]) - ord('0')
#           inc(i)
#         if frmt[i] == '}': inc(i)
#         else: raise newException(ValueError, "invalid format string")

#         add(result, args[j-1])
#       else: raise newException(ValueError, "invalid format string")
#     var start = i
#     while i < length:
#       if frmt[i] != '$': inc(i)
#       else: break
#     if i - 1 >= start:
#       add(result, substr(frmt, start, i - 1))


# proc addf*(c: var Rope, frmt: string, args: openArray[Rope]) {.rtl, extern: "nro$1".} =
#   ## Shortcut for `add(c, frmt % args)`.
#   runnableExamples:
#     var r = rope("Dash: ")
#     r.addf "$1 $2 $3", [rope("Nim"), rope("is"), rope("a great language")]
#     doAssert $r == "Dash: Nim is a great language"

#   add(c, frmt % args)

when not defined(js) and not defined(nimscript):
  const
    bufSize = 1024 # 1 KB is reasonable

  proc equalsFile*(r: Rope, f: File): bool {.rtl, extern: "nro$1File".} =
    ## Returns true if the contents of the file `f` equal `r`.
    var
      buf: array[bufSize, char]
      bpos = buf.len
      blen = buf.len

    for s,l in leaves(r):
      var spos = 0
      let slen = l
      while spos < slen:
        if bpos == blen:
          # Read more data
          bpos = 0
          blen = readBuffer(f, addr(buf[0]), buf.len)
          if blen == 0: # no more data in file
            return false
        let n = min(blen - bpos, slen - spos)
        # TODO: There's gotta be a better way of comparing here...
        if not equalMem(addr(buf[bpos]),
                        cast[pointer](cast[int](s) + spos), n):
          return false
        spos += n
        bpos += n

    result = readBuffer(f, addr(buf[0]), 1) == 0 # check that we've read all

  proc equalsFile*(r: Rope, filename: string): bool {.rtl, extern: "nro$1Str".} =
    ## Returns true if the contents of the file `f` equal `r`. If `f` does not
    ## exist, false is returned.
    var f: File
    result = open(f, filename)
    if result:
      result = equalsFile(r, f)
      close(f)

{.pop.}
