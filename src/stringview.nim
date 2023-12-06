#
#
#        (c) Copyright 2023 Alireza Radkesvat
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#          


# since nim views and borrow checker are still experimental, 
# this module was created to implement a efficent copy-less string buffer
# with shifting and reallocation ability, reservations, more..
# look at the test file for general usage
#
# made for orc gc in mind

import stew/byteutils, math, ptrops, sequtils

export ptrops

const log_hooks {.booldefine.} = false
const ncstr = defined(nimSeqsV2) #yard said don't do that :(
const setStrLitFlag = ncstr #god help us on that
const strlitFlag = 1 shl (sizeof(int)*8 - 2)

logScope:
    topic = "StringView"
    #memoryUsage = currentMemUsage()


type
    PayloadBase = object
        cap: int
    Payload = object
        cap: int #fake cap / same as len
        data: UncheckedArray[char]

    StringView* {.acyclic.} = ref object of RootRef
        lenpos: int
        curpos: int
        cap: int
        pbuf: ptr Payload # buffer pointer
        backup: int       #low level, to prevent a copy
        exportflag: bool
        views: seq[View]

    View* = ref object
        at*: ptr UncheckedArray[char]
        offset: int
when ncstr:
    type
        NimStringV2 = object
            len: int
            p: ptr Payload ## can be nil if len == 0.
        NimSeqV2 = NimStringV2



template contentSize(cap): int = cap + 1 + sizeof(PayloadBase)

# how much data you can read ? or shift ofc
proc `len`*(v: StringView | typeof(StringView()[])): int {.inline.} = v.lenpos - v.curpos



# using buf function you have these
proc `high`*(v: StringView | typeof(StringView()[])): int = v.len - 1
proc `low`*(v: StringView | typeof(StringView()[])): int = 0


# this is the buffer, you can use for reading or writing to it
template buf*(v: StringView | typeof(StringView()[])): ptr UncheckedArray[char] =
    cast[ptr UncheckedArray[char]](addr v.pbuf.data[v.curpos])



# how many bytes we can fill without realloc
proc lCap*(v: StringView | typeof(StringView()[])): int {.inline.} = v.curpos
proc rCap*(v: StringView | typeof(StringView()[])): int {.inline.} = (v.cap * 2 - v.curpos)


proc safeAfterExport(v: StringView) =
    when ncstr:
        if v.exportflag:
            (cast[ptr Payload](v.buf().offset -sizeof(PayloadBase))).cap = v.backup
    else: discard

proc `=destroy`*(x: typeof(StringView()[])) =
    when log_hooks: echo "=destroy StringView"

    if x.pbuf != nil:
        when compileOption("threads"):
            deallocShared(x.pbuf)
        else:
            dealloc(x.pbuf)

proc `=copy`*(a: var typeof(StringView()[]); b: typeof(StringView()[])) {.error: "not for me!".} =
    # do nothing for self-assignments:

    if a.pbuf == b.pbuf: return
    when log_hooks: echo "=copy StringView"

    `=destroy`(a)
    wasMoved(a)

    a.lenpos = b.lenpos
    a.curpos = b.curpos
    a.cap = b.cap
    a.backup = b.backup
    a.exportflag = b.exportflag
    a.views = b.views

    if b.pbuf != nil:
        let realcap = a.cap * 2
        when compileOption("threads"):
            a.pbuf = cast[typeof(a.pbuf)](allocShared((contentSize realcap)))
        else:
            a.pbuf = cast[typeof(a.pbuf)](alloc((contentSize realcap)))

        copyMem(addr a.pbuf.data[0], addr b.pbuf.data[0], a.cap *2 + 1)

proc `=dup`*(a: typeof(StringView()[])): typeof(StringView()[]) {.nodestroy, error: "not for me!".} =
    # an optimized version of `=wasMoved(tmp); `=copy(tmp, src)`
    # usually present if a custom `=copy` hook is overridden
    when log_hooks: echo "=dup StringView"

    a.lenpos = b.lenpos
    a.curpos = b.curpos
    a.cap = b.cap
    a.backup = b.backup
    a.exportflag = b.exportflag
    a.views = b.views

    if b.pbuf != nil:
        let realcap = a.cap * 2
        when compileOption("threads"):
            a.pbuf = cast[typeof(a.pbuf)](allocShared((contentSize realcap)))
        else:
            a.pbuf = cast[typeof(a.pbuf)](alloc((contentSize realcap)))

        copyMem(addr a.pbuf.data[0], addr b.pbuf.data[0], a.cap *2 + 1)

proc `=sink`*(a: var typeof(StringView()[]); b: typeof(StringView()[])) =
    # move assignment, optional.
    # Compiler is using `=destroy` and `copyMem` when not provided
    when log_hooks: echo "=sink StringView"
    `=destroy`(a)
    wasMoved(a)
    a.lenpos = b.lenpos
    a.curpos = b.curpos
    a.cap = b.cap
    a.pbuf = b.pbuf
    a.backup = b.backup
    a.exportflag = b.exportflag
    var v {.cursor.} = b.views
    a.views = move(v)
    wasMoved(v)
    assert b.views.len == 0

    # var size = b.views.len() * 2
    # a.views = newSeqOfCap[ptr View](cap = size)

    # for i in 0..b.views.high:
    #     a.views[i] = b.views[i]
    #     a.views[i].owner = addr (a[])
    # b.views.setLen(0)
    # wasMoved(b.views)

# exporting to string without copy ... Hmm not needed this because we use seq[byte]
# template withString*(v: StringView; name: untyped; code: untyped) =
#     var name{.inject, cursor.}: string
#     when ncstr:
#         safeAfterExport(v)
#         v.exportflag = true
#         var p: ptr Payload = cast[ptr Payload](v.buf().offset -sizeof(PayloadBase))
#         v.backup = p.cap
#         p.cap = v.len
#         when setStrLitFlag:
#             p.cap = strlitFlag or p.cap
#         p.data[v.len] = 0.char
#         name = cast[string](NimStringV2(len: v.len, p: p))
#     else:
#         name = string.fromBytes(toOpenArray(cast[ptr UncheckedArray[byte]](v.buf), 0, v.high))

#     block:
#         defer:
#             safeAfterExport(v)
#         code
proc `$`*(v: StringView): string = string.fromBytes(toOpenArray(cast[ptr UncheckedArray[byte]](v.buf), 0, v.high))

# gives you the buffer as a seq[char] without copy, enjoy
template bytes*(v: StringView; name: untyped; code: untyped) =
    var name{.inject, cursor.}: seq[byte]
    when ncstr:
        safeAfterExport(v)
        v.exportflag = true
        var p: ptr Payload = cast[ptr Payload](v.buf().offset -sizeof(PayloadBase))
        v.backup = p.cap
        p.cap = v.len
        name = cast[seq[byte]](NimSeqV2(len: v.len, p: p))
        return res
    else:
        name = @(toOpenArrayByte(v.buf(), 0, v.high))
    block:
        defer:
            safeAfterExport(v)
        code


proc cstring*(v: StringView): cstring =
    v.buf[v.len] = 0.char
    return cast[cstring](v.buf)


# when you need more size
proc expand(v: StringView; increase: int) =
    let newcap = pow(2, ceil(log2((v.cap*2).float + (increase.float*2)))).int
    warn "allocated more memory! ", oldcap = v.cap*2, increase, newcap

    when compileOption("threads"):
        v.pbuf = cast[ptr Payload](reallocShared(v.pbuf, contentSize newcap))
    else:
        v.pbuf = cast[ptr Payload](realloc(v.pbuf, contentSize newcap))

    let dif = (newcap div 2) - v.cap

    moveMem(addr v.pbuf.data[dif], addr v.pbuf.data[0], v.cap*2)

    v.curpos += dif
    v.lenpos += dif
    # info "positions", cur =  v.curpos
    for track in v.views:
        track.offset = dif+track.offset
        track.at = cast[ptr UncheckedArray[char]](addr v.pbuf.data[track.offset])
    v.pbuf.data[newcap] = 0.char


    v.cap = newcap div 2


# simply writes to buf() , you can use of toOpenArray for your type to write witohut copy
proc write*(v: StringView; d: openArray[byte|char]) =
    if v.rCap < d.len:
        expand(v, (d.len - v.rCap))
    copyMem(v.buf(), addr d[0], d.len)
    v.lenpos = v.curpos + d.len

# bad idea but we try to move your string
proc write*(v: StringView; d: sink string) =
    v.write(d.toOpenArrayByte(d.low, d.high))


template reserve*(v: StringView; bytes: int) =
    v.setLen(v.len + bytes)

template consume*(v: StringView; bytes: int) =
    v.setLen(v.len - bytes)

proc setLen*(v: StringView; ln: int) =
    assert ln >= 0
    if v.rCap < ln:
        expand(v, (ln - v.rCap))
    v.lenpos = v.curpos + ln

# most efficent way of reading/writing fixed size data
proc view*(v: StringView; bytes: int): View =
    assert bytes != 0
    assert v.curpos + bytes <= v.cap * 2, "cap = " & $(v.cap*2) & "cur = " & $v.curpos
    result = new View
    result.offset = v.curpos
    result.at = cast[ptr UncheckedArray[char]](addr v.pbuf.data[v.curpos])
    v.views.add result

proc isValid*(strv: StringView; v: View): bool = strv.views.contains v


proc shiftl*(v: StringView; bytes: int) =
    if v.lCap < bytes:
        expand(v, (bytes - v.lCap))
    v.curpos -= bytes


proc shiftr*(v: StringView; bytes: int) =
    assert v.curpos + bytes <= v.lenpos # we can but dont want negative len !
    if v.rCap < bytes:
        expand(v, (bytes - v.rCap))
    v.curpos += bytes




# reset the state, everything but don't lose allocation
# after this call, all views are invalid !
proc reset*(v: var StringView) =
    v.lenpos = v.cap
    v.curpos = v.cap
    v.backup = 0
    v.exportflag = false
    v.views.setLen 0

proc newStringView*(cap: int = 256): StringView =
    assert cap >= 0
    new result
    let realcap = cap * 2
    when compileOption("threads"):
        result.pbuf = cast[ptr Payload](allocShared(contentSize realcap))
    else:
        result.pbuf = cast[ptr Payload](alloc(contentSize realcap))

    result.cap = cap
    result.lenpos = cap
    result.curpos = cap
    result.backup = 0
    result.exportflag = false
    result.views = newSeqOfCap[View](cap = 200)







