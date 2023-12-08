import rope, stew/byteutils, stringview, chronos, hashes

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

    Tunnel*{.acyclic.} = ref object of Rootref
        name*: string
        hash: Hash

        ties: array[Chains, Chain]
        hsize: int
        rv*: StringView
        wv*: StringView
        readBuffer*: View
        writeBuffer*: View

    #raised when a tunnel dose not satisfy to continue the process
    FlowError = object of CatchableError
        tunnel: Tunnel
    FlowReadError* = ref object of FlowError
    FlowWriteError* = ref object of FlowError

proc `==`*(x, y: InfoTag): bool {.borrow.}
proc `$`*(x: InfoTag): string {.borrow.}

template name*(self: Tunnel): string = self.name
template hsize*(self: Tunnel): int = self.hsize

method init*(self: Tunnel, name: string, hsize: static[int]){.base, gcsafe.} =
    self.name = name
    self.hash = hash(name)
    self.hsize = hsize
    #some other init things for any tunnel ?



template writeChecks*(self: Tunnel, sv: StringView, writebody: untyped) =
    self.wv = sv
    assert self.wv != nil
    self.wv.shiftl(self.hsize)
    self.writeBuffer = self.wv.view(self.hsize)
    self.wv.shiftr(self.hsize)
    block writebodyImpl:
        defer: self.wv.shiftl(self.hsize)
        writebody




template readChecks*(self: Tunnel, sv: StringView, readbody: untyped) =
    block readchecks:
        self.rv = sv
        assert self.rv != nil
        if self.rv.len < self.hsize:
            error "stream finished before full header was read.", tunnel = self.name, hsize = self.hsize
            self.rv.reset()
            raise FlowReadError(msg: "stream finished before full header was read.", tunnel: self)
            break readchecks
        self.readBuffer = self.rv.view(self.hsize)
        self.rv.shiftr(self.hsize)
        block body:
            readbody


method requestInfo*(self: Tunnel, target: Hash, dir: SigDirection, tag: InfoTag, chain: Chains = default): ref InfoBox {.base, gcsafe.} =
    case dir:
        of left:
            if self.ties[chain].prev != nil:
                self.ties[chain].prev.requestInfo(target, dir, tag, chain)
            else: nil
        of right:
            if self.ties[chain].next != nil:
                self.ties[chain].next.requestInfo(target, dir, tag, chain)
            else: nil
        of both:
            var res: ref InfoBox = nil
            if self.ties[chain].next != nil:
                res = self.ties[chain].next.requestInfo(target, right, tag, chain)
            if res == nil and  self.ties[chain].prev != nil:
                res = self.ties[chain].prev.requestInfo(target, left, tag, chain)
            res

template requestInfo*(self: Tunnel, target: string, dir: SigDirection, tag: InfoTag, chain: Chains = default): ref InfoBox =
    requestInfo(self, hash(target), dir, tag, chain)









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


proc isMe*(self: Tunnel, hash: Hash): bool = self.hash == hash
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
    let next = self.ties[chain].next
    assert not next.isNil
    return next.write(data, chain)



method read*(self: Tunnel, chain: Chains = default): Future[StringView] {.base gcsafe.} =
    # return self.next.read()
    let next = self.ties[chain].next
    assert not next.isNil
    return next.read()




# type Adapter* = ref object of Tunnel
#     discard

# method write*(self: Adapter, data: Rope): Future[void] =
#     quit "Implenet Adapter write"

# method read*(self: Adapter): Future[StringView] =
#     quit "Implenet Adapter read"

# method connect*(self: Adapter) =
#     quit "Implenet Adapter connect"

# method disconnect*(self: Adapter): Rope =
#     quit "Implenet Adapter read"
