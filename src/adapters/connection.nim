import tunnel, store
import chronos/transports/stream


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
    bufferSize = 4093
    writeTimeOut = 2
    readTimeOut = 200


proc getRawSocket*(self: ConnectionAdapter): StreamTransport {.inline.} = self.socket

# called when we are on the right side
proc readloop(self: ConnectionAdapter){.async.} =
    #read data from chain, write to socket
    var socket = self.socket
    var sv: StringView = nil
    while not self.stopped:
        try:
            sv = await procCall read(Tunnel(self), 1)
            trace "Readloop Read", bytes = sv.len
        except [CancelledError, FlowError,AsyncChannelError]:
            var e = getCurrentException()
            warn "Readloop Cancel [Read]", msg = e.name
            if not self.stopped: signal(self, both, close)
            return
        except CatchableError as e:
            error "Readloop Unexpected Error, [Read]", name = e.name, msg = e.msg
            quit(1)


        try:
            trace "Readloop write to socket", count = sv.len
            if sv.len != await socket.write(sv.buf, sv.len).wait(writeTimeOut.seconds):
                raise newAsyncStreamIncompleteError()

        except [CancelledError, FlowError,AsyncTimeoutError,TransportError,AsyncChannelError, AsyncStreamError]:
            var e = getCurrentException()
            warn "Readloop Cancel [Write]", msg = e.name
            if not self.stopped: signal(self, both, close)
            return
        except CatchableError as e:
            error "Readloop Unexpected Error, [Write]", name = e.name, msg = e.msg
            quit(1)
        finally:
            self.store.reuse move sv



proc writeloop(self: ConnectionAdapter){.async.} =
    #read data from socket, write to chain
    var socket = self.socket
    var sv: StringView = nil
    while not self.stopped:
        try:
            sv = self.store.pop()
            sv.reserve(bufferSize)
            var actual = await socket.readOnce(sv.buf(), bufferSize).wait(readTimeOut.seconds)
            if actual == 0:
                trace "Writeloop read 0 !";
                self.store.reuse move sv
                if not self.stopped: signal(self, both, close)
                break
            else:
                trace "Writeloop read", bytes = actual
            sv.setLen(actual)

        except [CancelledError, TransportError,AsyncTimeoutError,AsyncChannelError]:
            var e = getCurrentException()
            trace "Writeloop Cancel [Read]", msg = e.name
            self.store.reuse sv
            if not self.stopped: signal(self, both, close)
            return
        except CatchableError as e:
            error "Writeloop Unexpected Error [Read]", name = e.name, msg = e.msg
            quit(1)



        try:
            trace "Writeloop write", bytes = sv.len
            await procCall write(Tunnel(self), move sv)

        except [CancelledError, FlowError,AsyncChannelError]:
            var e = getCurrentException()
            trace "Writeloop Cancel [Write]", msg = e.name
            if sv != nil:self.store.reuse sv
            if not self.stopped: signal(self, both, close)
            return
        except CatchableError as e:
            error "Writeloop Unexpected Error [Write]", name = e.name, msg = e.msg
            quit(1)




proc init(self: ConnectionAdapter, name: string, socket: StreamTransport, store: Store){.raises: [].} =
    procCall init(Adapter(self), name, hsize = 0)
    self.socket = socket
    self.store = store
    assert not self.socket.closed()


proc newConnectionAdapter*(name: string = "ConnectionAdapter", socket: StreamTransport, store: Store): ConnectionAdapter {.raises: [].} =
    result = new ConnectionAdapter
    result.init(name, socket, store)
    trace "Initialized", name


method write*(self: ConnectionAdapter, rp: StringView, chain: Chains = default): Future[void] {.async.} =
    doAssert false, "you cannot call write of ConnectionAdapter!"

method read*(self: ConnectionAdapter, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    doAssert false, "you cannot call read of ConnectionAdapter!"


method start(self: ConnectionAdapter){.raises: [].} =
    {.cast(raises: []).}:
        procCall start(Adapter(self))
        trace "starting"

        self.readLoopFut = self.readloop()
        self.writeLoopFut = self.writeloop()
        asyncSpawn self.readLoopFut
        asyncSpawn self.writeLoopFut

proc stop*(self: ConnectionAdapter) =
    proc breakCycle(){.async.} =
        await sleepAsync(2.seconds)
        self.signal(both,breakthrough)

    if not self.stopped:
        trace "stopping"
        self.stopped = true
        if not isNil(self.socket): self.socket.close()
        if not isNil(self.readLoopFut): cancelSoon self.readLoopFut
        if not isNil(self.writeLoopFut): cancelSoon self.writeLoopFut
        asyncSpawn breakCycle()

method signal*(self: ConnectionAdapter, dir: SigDirection, sig: Signals, chain: Chains = default){.raises: [].} =
    if sig == close or sig == stop: self.stop()

    if sig == breakthrough: doAssert self.stopped, "break through signal while still running?"

    procCall signal(Tunnel(self), dir, sig, chain)

    if sig == start: self.start()


