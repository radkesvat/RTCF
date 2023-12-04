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
        readBuffer*: ptr UncheckedArray[byte]
        writeBuffer*: ptr UncheckedArray[byte]

method init(tun: Tunnel, name: string, hsize: static[int]){.base, raises: [], gcsafe.} =
    tun.name = name
    tun.hsize = hsize
    #some other init things for any tunnel ?



template writeChecks*(self: Tunnel, sv: StringView, initheader: untyped) =
    sv.shiftl(self.hsize)
    if self.wv != sv:
        let op = self.writeBuffer
        let np = sv.view(self.hsize)
        if op != nil:
            copyMem(np, op, self.hsize)
        self.writeBuffer = np
        self.wv = sv
        block writeChecksInitHeader:
            initheader
        # self.wv.shiftl(self.hsize)

template readChecks*(self: Tunnel, sv: StringView, initheader: untyped) =
    if self.rv != sv:
        let op = self.readBuffer
        let np = sv.view(self.hsize)
        sv.shiftr(self.hsize)
        if op != nil:
            copyMem(np, op, self.hsize)
        self.readBuffer = np
        self.rv = sv
        block readChecksInitHeader:
            initheader
    else:
        sv.shiftr(self.hsize)


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
