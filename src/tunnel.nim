import rope, stew/byteutils, stringview, chronos

export rope, byteutils, stringview, chronos

logScope:
    topic = "Tunnel"

type
    Chains* = enum
        default,
        alternative

    Chain* {.acyclic.} = object
        prev*, next*: Tunnel

    Tunnel*{.acyclic.} = ref object of Rootref
        name: string
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


method init(tun: Tunnel, name: string, hsize: static[int]){.base, raises: [], gcsafe.} =
    tun.name = name
    tun.hsize = hsize
    #some other init things for any tunnel ?



template writeChecks*(self: Tunnel, sv: StringView, writebody: untyped) =
    assert sv != nil
    self.wv = sv
    self.wv.shiftl(self.hsize)
    let first = self.writeBuffer == nil
    self.writeBuffer = self.wv.view(self.hsize)
    self.wv.shiftr(self.hsize)
    block writebodyImpl:
        defer: self.wv.shiftl(self.hsize)
        let firstwrite {.inject.} = first
        writebody




template readChecks*(self: Tunnel, sv: StringView, readbody: untyped) =
    assert sv != nil
    block readchecks:
        self.rv = sv
        let first = self.writeBuffer == nil

        if self.rv.len < self.hsize:
            error "stream finished before full header was read.", tunnel = self.name, hsize = self.hsize
            self.rv.reset()
            raise FlowReadError(msg: "stream finished before full header was read.", tunnel: self)
            break readchecks
        self.readBuffer = self.rv.view(self.hsize)
        self.rv.shiftr(self.hsize)
        block body:
            let firstread {.inject.} = first
            readbody




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

proc chain*(`from`: Tunnel, `to`: Tunnel, chainfrom: Chains = default, chainto: Chains = default): Tunnel {.raises: [], gcsafe, discardable.} =
    `from`.ties[chainfrom].next = `to`
    `to`.ties[chainto].prev = `from`
    `to`


# template next*(self: Tunnel): Tunnel = self.main.next
# template prev*(self: Tunnel): Tunnel = self.main.prev


# template nextAlt*(self: Tunnel): Tunnel = self.alt.next
# template prevAlt*(self: Tunnel): Tunnel = self.alt.prev

template name*(self: Tunnel): string = self.name
template hsize*(self: Tunnel): int = self.hsize
template `name=`*(self: Tunnel, name: string) = self.name = name


# proc init*(t: Tunnel,tag:TunnelTag = TunnelTag.None, name = "unnamed tunenl") =
#     t.tag = tag
#     t.name = name


method write*(self: Tunnel, data: StringView, chain: Chains = default): Future[void] {.base, raises: [], gcsafe.} =
    let next = self.ties[chain].next
    assert not next.isNil
    return next.write(data, chain)



method read*(self: Tunnel, chain: Chains = default): Future[StringView] {.base, raises: [], gcsafe.} =
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
