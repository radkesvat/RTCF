import tunnel, strutils, store
import sequtils, chronos/transports/stream
# This module unfortunately has global shared memory as part of its state

logScope:
    topic = "Connection Adapter"


#     1    2    3    4    5    6    7 ...
# ---------------------------------------------------
#                 User Requets
# ---------------------------------------------------
#     Connection contains variable lenght data      |
# ---------------------------------------------------


type
    ConnectionAdapter* = ref object of Adapter
        socket: StreamTransport
        readLoopFut: Future[void]
        writeLoopFut: Future[void]
        store: Store

const
    bufferSize = 4096


proc getRawSocket*(self: ConnectionAdapter): StreamTransport {.inline.} = self.socket

# called when we are on the right side
proc readloop(self: ConnectionAdapter){.async.} =
    #read data from chain, write to socket
    var socket = self.socket
    try:
        while not socket.closed and not self.stopped:
            var sv = await procCall read(Tunnel(self), 1)
            if sv.len != await socket.write(sv.buf, sv.len):
                raise newAsyncStreamIncompleteError()
    except CatchableError as e:
        trace "Read Loop finished with ", exception = e.msg
    self.signal(both, close)

proc writeloop(self: ConnectionAdapter){.async.} =
    #read data from socket, write to chain
    var socket = self.socket
    try:
        while not socket.closed and not self.stopped:
            var sv = self.store.pop()
            sv.reserve(bufferSize)
            var actual = await socket.readOnce(sv.buf(), bufferSize)
            if actual == 0:
                trace "close for 0 bytes read from socket"; break

            sv.setLen(actual)
            await procCall write(Tunnel(self), sv)
    except CatchableError as e:
        trace "Write Loop finished with ", exception = e.msg
    self.signal(both, close)


method init(self: ConnectionAdapter, name: string, socket: StreamTransport, store: Store): ConnectionAdapter =
    self.socket = socket
    self.store = store
    procCall init(Adapter(self), name, hsize = 0)



proc new*(t: typedesc[ConnectionAdapter], name: string = "ConnectionAdapter", socket: StreamTransport, store: Store): ConnectionAdapter =
    result = new ConnectionAdapter
    result.init(name, socket, store)
    trace "Initialized new ConnectionAdapter", name


method write*(self: ConnectionAdapter, rp: StringView, chain: Chains = default): Future[void] {.async.} =
    doAssert false, "you cannot call write of ConnectionAdapter!"

method read*(self: ConnectionAdapter, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    doAssert false, "you cannot call read of ConnectionAdapter!"



proc start(self: ConnectionAdapter) =
    {.cast(raises: []).}:
        self.readLoopFut = self.readloop()
        self.writeLoopFut = self.writeloop()

method signal*(self: ConnectionAdapter, dir: SigDirection, sig: Signals, chain: Chains = default) =
    var broadcast = false
    if sig == close or sig == stop:
        broadcast = not self.stopped
        self.stopped = true
        cancelSoon self.readLoopFut
        cancelSoon self.writeLoopFut
        self.socket.close()

    if sig == start: self.start()

    if broadcast: procCall signal(Tunnel(self), dir, sig, chain)


    if sig == breakthrough: doAssert self.stopped, "break through signal while still running?"


