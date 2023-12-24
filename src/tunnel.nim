import stew/byteutils, stringview, chronos, hashes
from threading/channels import AsyncChannelError

export byteutils, stringview, chronos, hashes

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
        readHeaderBuf: ptr UncheckedArray[byte]
        writeHeaderBuf: ptr UncheckedArray[byte]
        stopped*: bool

    #raised when a tunnel dose not satisfy to continue the process
    FlowError* = ref object of CatchableError
    FlowCloseError* = ref object of FlowError
    FlowReadError* = ref object of FlowError
    InsufficientBytse* = ref object of FlowReadError
    FlowWriteError* = ref object of FlowError

    CancelErrors* = AsyncChannelError or FlowError or CancelledError

proc `==`*(x, y: InfoTag): bool {.borrow.}
proc `$`*(x: InfoTag): string {.borrow.}

template name*(self: Tunnel): string = self.name
template hsize*(self: Tunnel): int = self.hsize

template getReadHeader*(self: Tunnel): ptr UncheckedArray[byte] = self.readHeaderBuf
template getWriteHeader*(self: Tunnel): ptr UncheckedArray[byte] = self.writeHeaderBuf


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
        self.writeHeaderBuf = new_stringview.buf()
        new_stringview.shiftr(self.hsize)
        self.writeLine = new_stringview
    block:
        body
    writeHeaderFinish(self)


proc setReadHeader*(self: Tunnel, sv: StringView) {.gcsafe, raises: [InsufficientBytse].} =
    let new_stringview = sv; assert new_stringview != nil
    if self.readLine != new_stringview:
        if new_stringview.len < self.hsize:
            error "stream finished before full header was read.", tunnel = self.name, hsize = self.hsize
            raise InsufficientBytse(msg: "stream finished before full header was read.")
        self.readHeaderBuf = new_stringview.buf()
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

proc findByName*(self: Tunnel, target: string or Hash, dir: SigDirection, chain: Chains = default): tuple[t: Tunnel, s: SigDirection] =
    var target = when target is string: hash(target) else: target
    template `is`(self: Tunnel, hash: Hash): bool = self.hash == hash

    if self is target: return (self, dir)
    case dir:
        of left:
            if self.ties[chain].prev != nil:
                self.ties[chain].prev.findByName(target, dir, chain)
            else: (nil, left)
        of right:
            if self.ties[chain].next != nil:
                self.ties[chain].next.findByName(target, dir, chain)
            else: (nil, right)
        of both:
            var res: tuple[t: Tunnel, s: SigDirection]
            if self.ties[chain].next != nil:
                res = self.ties[chain].next.findByName(target, right, chain)
            if res.t == nil and self.ties[chain].prev != nil:
                res = self.ties[chain].prev.findByName(target, left, chain)
            res

proc findByType*(self: Tunnel, target: typedesc, dir: SigDirection, chain: Chains = default): tuple[t: target, s: SigDirection] =
    case dir:
        of left:
            if self.ties[chain].prev != nil:
                if self.ties[chain].prev is target: return (target(self.ties[chain].prev), left)
                else: self.ties[chain].prev.findByType(target, dir, chain)
            else: (nil, left)
        of right:
            if self.ties[chain].next != nil:
                if self.ties[chain].next is target: return (target(self.ties[chain].next), right)
                else: self.ties[chain].next.findByType(target, dir, chain)
            else: (nil, right)
        of both:
            var res: tuple[t: target, s: SigDirection]
            if self.ties[chain].next != nil:
                res = self.ties[chain].next.findByType(target, right, chain)
            if res.t == nil and self.ties[chain].prev != nil:
                res = self.ties[chain].prev.findByType(target, left, chain)
            res

#very general ! you may use direct functions
method requestInfo*(self: Tunnel, targethash: Hash, dir: SigDirection, tag: InfoTag, chain: Chains = default): ref InfoBox {.base, gcsafe.} =
    var (target, dir) = self.findByName(targethash, dir, chain)
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

proc getNext*(self: Tunnel, chain: Chains = default): Tunnel {.inline, gcsafe.} = self.ties[chain].next
proc getPrev*(self: Tunnel, chain: Chains = default): Tunnel {.inline, gcsafe.} = self.ties[chain].prev


method write*(self: Tunnel, data: StringView, chain: Chains = default): Future[void] {.base, gcsafe.} =
    var next = self.ties[chain].next
    assert not next.isNil
    resetWriteState self
    return next.write(data, chain)



method read*(self: Tunnel, bytes: int, chain: Chains = default): Future[StringView] {.base gcsafe.} =
    # return self.next.read()
    var next = self.ties[chain].next
    assert not next.isNil
    resetReadState self
    return next.read(bytes, chain)




type
    Location* = enum
        BeforeGfw, AfterGfw

    Side* {.pure.} = enum
        Left, Right

    Adapter* = ref object of Tunnel
        location*: Location
        side*: Side

method init*(self: Adapter, name: string, hsize: static[int]){.base, gcsafe.} =
    procCall init(Tunnel(self), name, hsize = hsize)

    if self.getNext != nil:
        doAssert self.getPrev == nil, "Adapters rule broken, the chain is not finished."
        self.side = Side.Left
    else:
        self.side = Side.Right

# method write*(self: Adapter, data: Rope): Future[void] =
    #     quit "Implenet Adapter write"

    # method read*(self: Adapter): Future[StringView] =
    #     quit "Implenet Adapter read"

    # method connect*(self: Adapter) =
    #     quit "Implenet Adapter connect"

    # method disconnect*(self: Adapter): Rope =
    #     quit "Implenet Adapter read"
