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

import stew/byteutils, math, ptrops

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

    StringView* = ref object of RootRef
        # buflen: int       # reserved since 0 from cap
        lenpos: int
        curpos: int
        cap: int
        pbuf: ptr Payload # buffer pointer
        saved: int        #low level
        exportflag: bool


when ncstr:
    type
        NimStringV2 = object
            len: int
            p: ptr Payload ## can be nil if len == 0.
        NimSeqV2 = NimStringV2



template contentSize(cap): int = cap + 1 + sizeof(PayloadBase)



# proc `cur`*(v: StringView | typeof(StringView()[])): int {.inline.} = v.curpos - v.cap

proc `len`*(v: StringView | typeof(StringView()[])): int {.inline.} = v.lenpos - v.curpos


#private ! they mapped to real buffer and start from 0
# template `high`(v: StringView | typeof(StringView()[])): int = v.buflen - 1
# template `low`(v: StringView | typeof(StringView()[])): int = v.offset.int

proc `high`*(v: StringView | typeof(StringView()[])): int = v.len - 1
proc `low`*(v: StringView | typeof(StringView()[])): int = 0

# buffer and len for user

template buf*(v: StringView | typeof(StringView()[])): ptr UncheckedArray[char] =
    cast[ptr UncheckedArray[char]](addr v.pbuf.data[v.curpos])



#how many bytes we can fill without realloc
proc lCap*(v: StringView | typeof(StringView()[])): int {.inline.} = v.curpos

proc rCap*(v: StringView | typeof(StringView()[])): int {.inline.} = (v.cap * 2 - v.curpos)


proc safeAfterExport(v: StringView) =
    when ncstr:
        if v.exportflag:
            (cast[ptr Payload](v.buf().offset -sizeof(PayloadBase))).cap = v.saved
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
    a.saved = b.saved
    a.exportflag = b.exportflag

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
    a.saved = b.saved
    a.exportflag = b.exportflag

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
    a.saved = b.saved
    a.exportflag = b.exportflag

# exporting to string will have 1 copy!
# template withString*(v: StringView; name: untyped; code: untyped) =
#     var name{.inject, cursor.}: string
#     when ncstr:
#         safeAfterExport(v)
#         v.exportflag = true
#         var p: ptr Payload = cast[ptr Payload](v.buf().offset -sizeof(PayloadBase))
#         v.saved = p.cap
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

template bytes*(v: StringView; name: untyped; code: untyped) =
    var name{.inject, cursor.}: seq[byte]
    when ncstr:
        safeAfterExport(v)
        v.exportflag = true
        var p: ptr Payload = cast[ptr Payload](v.buf().offset -sizeof(PayloadBase))
        v.saved = p.cap
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

proc calCap(v: StringView; increase: int) =
    let newcap = pow(2, ceil(log2((v.cap*2).float + (increase.float*2)))).int
    warn "allocated more memory! ",oldcap = v.cap*2 , increase , newcap

    when compileOption("threads"):
        v.pbuf = cast[ptr Payload](reallocShared(v.pbuf, contentSize newcap))
    else:
        v.pbuf = cast[ptr Payload](realloc(v.pbuf, contentSize newcap))

    let dif = (newcap div 2) - v.cap

    moveMem(addr v.pbuf.data[dif], addr v.pbuf.data[0], v.cap*2)
    v.curpos += dif
    v.lenpos += dif

    v.pbuf.data[newcap] = 0.char
    v.cap = newcap div 2


proc write*(v: StringView; d: openArray[byte|char]) =
    if v.rCap < d.len:
        calCap(v, (d.len - v.rCap))
    copyMem(v.buf(), addr d[0], d.len)
    v.lenpos = v.curpos + d.len

proc write*(v: StringView; d: sink string) =
    v.write(d.toOpenArrayByte(d.low, d.high))


template reserve*(v: StringView; bytes: int) =
    v.setLen(v.len + bytes)

template consume*(v: StringView; bytes: int) =
    v.setLen(v.len - bytes)

proc setLen*(v: StringView; ln: int) =
    assert ln >= 0
    if v.rCap < ln:
        calCap(v, (ln - v.rCap))
    v.lenpos = v.curpos + ln


proc view*(v: StringView; bytes: int): ptr UncheckedArray[byte] =
    assert bytes != 0
    assert v.curpos + bytes < v.cap * 2
    result = cast[ptr UncheckedArray[byte]](addr v.pbuf.data[v.curpos])

proc shiftl*(v: StringView; bytes: int) =
    # echo "lCap: ", v.lCap, " bytes:", bytes
    if v.lCap < bytes:
        calCap(v, (bytes - v.lCap))
    v.curpos -= bytes
    # v.lenpos += bytes


proc shiftr*(v: StringView; bytes: int) =
    assert v.curpos + bytes <= v.lenpos # never more than lenpos
    if v.rCap < bytes:
        calCap(v, (bytes - v.rCap))
    v.curpos += bytes
    # v.lenpos -= bytes

# proc setLen*(v: StringView | typeof(StringView()[]), len: int) {.inline.} = v.buflen = v.offset + len; assert v.cap >= v.buflen



# reset the state, everything but don't lose allocation
proc reset*(v: var StringView) =
    v.lenpos = v.cap 
    v.curpos = v.cap
    v.saved = 0
    v.exportflag = false

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
    result.saved = 0
    result.exportflag = false








