import rope, stew/byteutils, stringview, chronos, hashes, pretty

export rope, byteutils, stringview, chronos, hashes

logScope:
    topic = "Tunnel"

{.push raises: [].}

type
    Chains* = enum
        default,
        alternative

    Signals* = enum
        invalid,
        start,
        pause,
        resume,
        close,
        stop,
        breakthrough

    SigDirection* = enum
        left, right, both

    InfoTag* = distinct int

    InfoBox* = tuple[tag: InfoTag, size: int, value: pointer]

    Chain* {.acyclic.} = object
        prev*, next*: Tunnel

    Tunnel* {.acyclic.} = ref object of Rootref
        name*: string
        hash: Hash
        ties: array[Chains, Chain]
        hsize: int
        readLine*: StringView
        writeLine*: StringView
        readHeaderBuf: View
        writeHeaderBuf: View
        stopped*:bool

    #raised when a tunnel dose not satisfy to continue the process
    FlowError = object of CatchableError
        tunnel: Tunnel
    FlowReadError* = ref object of FlowError
    InsufficientBytse* = ref object of FlowReadError


    FlowWriteError* = ref object of FlowError

proc `==`*(x, y: InfoTag): bool {.borrow.}
proc `$`*(x: InfoTag): string {.borrow.}

template name*(self: Tunnel): string = self.name
template hsize*(self: Tunnel): int = self.hsize

template getReadHeader*(self: Tunnel): ptr UncheckedArray[char] = self.readHeaderBuf.at
template getWriteHeader*(self: Tunnel): ptr UncheckedArray[char] = self.writeHeaderBuf.at


method init*(self: Tunnel, name: string, hsize: static[int]){.base, gcsafe.} =
    self.name = name
    self.hash = hash(name)
    self.hsize = hsize
    #some other init things for any tunnel ?

proc resetWriteState(self: Tunnel) {.inline.} =
    system.reset self.writeLine
    system.reset self.writeHeaderBuf

proc resetReadState(self: Tunnel) {.inline.} =
    system.reset self.readLine
    system.reset self.readHeaderBuf

proc resetRWState(self: Tunnel) = resetWriteState(self); resetReadState(self)



template writeHeaderFinish*(self: Tunnel) = self.writeLine.shiftl(self.hsize)

template setWriteHeader*(self: Tunnel, sv: StringView, body: untyped) =
    let new_stringview = sv; assert new_stringview != nil
    if self.writeLine != new_stringview:
        new_stringview.shiftl(self.hsize)
        self.writeHeaderBuf = new_stringview.view(self.hsize)
        new_stringview.shiftr(self.hsize)
        self.writeLine = new_stringview
    block:
        body
    writeHeaderFinish(self)


proc setReadHeader*(self: Tunnel, sv: StringView) {.gcsafe, raises: [FlowReadError].} =
    let new_stringview = sv; assert new_stringview != nil
    if self.readLine != new_stringview:
        if new_stringview.len < self.hsize:
            error "stream finished before full header was read.", tunnel = self.name, hsize = self.hsize
            raise InsufficientBytse(msg: "stream finished before full header was read.", tunnel: self)
        self.readHeaderBuf = new_stringview.view(self.hsize)
        self.readLine = new_stringview

    self.readLine.shiftr(self.hsize)


method signal*(self: Tunnel, dir: SigDirection, sig: Signals, chain: Chains = default){.base, gcsafe.} =
    case dir:
        of left:
            if self.ties[chain].prev != nil:
                self.ties[chain].prev.signal(dir, sig, chain)
        of right:
            if self.ties[chain].next != nil:
                self.ties[chain].next.signal(dir, sig, chain)
        of both:
            if self.ties[chain].next != nil:
                self.ties[chain].next.signal(right, sig, chain)
            if self.ties[chain].prev != nil:
                self.ties[chain].prev.signal(left, sig, chain)
    case sig:
        of breakthrough:
            for c in mitems(self.ties): c.reset()
        else: discard


#for subs
template isMe*(self: Tunnel, target: string or Hash): bool =
    when target is string: self.hash == hash(target) else: self.hash == target

proc findByName*(self: Tunnel, target: string or Hash, dir: SigDirection, chain: Chains = default): Tunnel =
    var target = when target is string: hash(target) else: target
    template `is`(self: Tunnel, hash: Hash): bool = self.hash == hash

    if self is target: return self
    case dir:
        of left:
            if self.ties[chain].prev != nil:
                self.ties[chain].prev.findByName(target, dir, chain)
            else: nil
        of right:
            if self.ties[chain].next != nil:
                self.ties[chain].next.findByName(target, dir, chain)
            else: nil
        of both:
            var res: Tunnel = nil
            if self.ties[chain].next != nil:
                res = self.ties[chain].next.findByName(target, right, chain)
            if res == nil and self.ties[chain].prev != nil:
                res = self.ties[chain].prev.findByName(target, left, chain)
            res

proc findByType*(self: Tunnel, target: typedesc, dir: SigDirection, tag: InfoTag, chain: Chains = default): Tunnel =
    case dir:
        of left:
            if self.ties[chain].prev != nil:
                if self.ties[chain].prev is target: return self.ties[chain].prev
                else: self.ties[chain].prev.findByType(target, dir, tag, chain)
            else: nil
        of right:
            if self.ties[chain].next != nil:
                if self.ties[chain].next is target: return self.ties[chain].next
                else: self.ties[chain].next.findByType(target, dir, tag, chain)
            else: nil
        of both:
            var res: Tunnel = nil
            if self.ties[chain].next != nil:
                res = self.ties[chain].next.findByType(target, right, tag, chain)
            if res == nil and self.ties[chain].prev != nil:
                res = self.ties[chain].prev.findByType(target, left, tag, chain)
            res

#very general ! you may use direct functions 
method requestInfo*(self: Tunnel, targethash: Hash, dir: SigDirection, tag: InfoTag, chain: Chains = default): ref InfoBox {.base, gcsafe.} =
    var target = self.findByName(targethash, dir, chain)
    if target == nil: return nil
    return target.requestInfo(targethash, dir, tag, chain)

template requestInfo*(self: Tunnel, target: string, dir: SigDirection, tag: InfoTag, chain: Chains = default): ref InfoBox =
    requestInfo(self, hash(target), dir, tag, chain)
# method inBound*(self: Tunnel, `from`: Tunnel, chain: ChainTarget){.base, gcsafe, raises: [].} =
#     case chain:
#         of main:
#             self.main.prev = `from`
#         of alternative:
#             self.alternative.prev = `from`


# method outBound*(self: Tunnel, `to`: Tunnel, chain: ChainTarget){.base, gcsafe, raises: [].} =
#     case chain:
#         of main:
#             self.main.next = `to`
#         of alternative:
#             self.alternative.next = `to`

# method chain*(self: Tunnel, next: Tunnel, chainto: ChainTarget = main): Tunnel {.base, raises: [], gcsafe, discardable.} =
#     inBound(next, self, chainto)
#     outbound(self, next, chainto)
#     next

# proc chain*(`from`: Chain, `to`: Chain): Chain {. raises: [], gcsafe, discardable.} =
#     `to`.prev = `from`
#     `from`.next = `to`
#     `to`

proc chain*(`from`: Tunnel, `to`: Tunnel, chainfrom: Chains = default, chainto: Chains = default): Tunnel {.gcsafe, discardable.} =
    `from`.ties[chainfrom].next = `to`
    `to`.ties[chainto].prev = `from`
    `to`


# template next*(self: Tunnel): Tunnel = self.main.next
# template prev*(self: Tunnel): Tunnel = self.main.prev


# template nextAlt*(self: Tunnel): Tunnel = self.alt.next
# template prevAlt*(self: Tunnel): Tunnel = self.alt.prev


# template `name=`*(self: Tunnel, name: string) = self.name = name


# proc init*(t: Tunnel,tag:TunnelTag = TunnelTag.None, name = "unnamed tunenl") =
#     t.tag = tag
#     t.name = name


method write*(self: Tunnel, data: StringView, chain: Chains = default): Future[void] {.base, gcsafe.} =
    var next = self.ties[chain].next
    assert not next.isNil
    resetWriteState self
    return next.write(data, chain)



method read*(self: Tunnel, chain: Chains = default): Future[StringView] {.base gcsafe.} =
    # return self.next.read()
    var next = self.ties[chain].next
    assert not next.isNil
    resetReadState self
    return next.read()




type Adapter* = ref object of Tunnel
    discard

# method write*(self: Adapter, data: Rope): Future[void] =
#     quit "Implenet Adapter write"

# method read*(self: Adapter): Future[StringView] =
#     quit "Implenet Adapter read"

# method connect*(self: Adapter) =
#     quit "Implenet Adapter connect"

# method disconnect*(self: Adapter): Rope =
#     quit "Implenet Adapter read"
