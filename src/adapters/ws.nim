import tunnel, store, websock/websock



logScope:
    topic = "Websocket Adapter"


#     1    2    3    4    5    6    7 ...
# ---------------------------------------------------
#                 User Requets
# ---------------------------------------------------
#     Websocket contains variable lenght data      |
# ---------------------------------------------------


type
    CloseCb = proc(): void {.raises: [], gcsafe.}
    WebsocketAdapter* = ref object of Adapter
        socketw: WSSession
        socketr: WSSession
        store: Store
        onClose: CloseCb
        discardReadFut:Future[void]

const writeTimeOut = 700.milliseconds
const pingInterval = 60.seconds

proc stop*(self: WebsocketAdapter) =
    proc breakCycle(){.async.} =
        await sleepAsync(2.seconds)
        self.signal(both, breakthrough)

    if not self.stopped:
        trace "stopping"
        self.stopped = true
        self.discardReadFut.cancelSoon()
        asyncSpawn self.socketr.close()
        asyncSpawn self.socketw.close()
        if not isNil(self.onClose): self.onClose()
        discard breakCycle()



proc discardRead(self: WebsocketAdapter){.async.}=
    var buf = allocShared(20)
    defer:
        deallocShared buf
    try:
        while not self.stopped: discard self.socketw.recv(buf,20)
    except :
        discard
        
proc keepAlive(self: WebsocketAdapter){.async.} =
    while not self.stopped:
        try:
            await sleepAsync(pingInterval)
            await self.socketw.ping(@[1.byte])
            await self.socketr.ping(@[1.byte])
        except:
            error "Failed to ping socket"
            self.stop()



proc init(self: WebsocketAdapter, name: string, socketr: WSSession, socketw: WSSession, store: Store, onClose: CloseCb) {.raises: [].} =
    procCall init(Adapter(self), name, hsize = 0)
    self.socketr = socketr
    self.socketw = socketw
    self.store = store
    self.onClose = onClose
    self.discardReadFut = discardRead(self)

proc newWebsocketAdapter*(name: string = "WebsocketAdapter", socketr: WSSession, socketw: WSSession, store: Store,
        onClose: CloseCb): WebsocketAdapter {.raises: [].} =
    result = new WebsocketAdapter
    result.init(name, socketr, socketw, store, onClose)
    trace "Initialized", name


method write*(self: WebsocketAdapter, rp: StringView, chain: Chains = default): Future[void] {.async.} =
    try:
        rp.bytes(byteseq):
            await self.socketw.send(byteseq, Binary).wait(writeTimeOut)
            trace "written bytes to ws socket", bytes = byteseq.len
    except CatchableError as e:
        self.stop; raise e
    finally:
        self.store.reuse rp


method read*(self: WebsocketAdapter, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    var sv = self.store.pop()
    try:
        trace "asking for ", bytes = bytes
        sv.reserve bytes
        var bytesread = await self.socketr.recv(cast[ptr byte](sv.buf), bytes)

        trace "received", bytes = bytesread

        if bytesread == bytes:
            return sv
        else:
            if bytesread == 0:
                trace "received 0 bytes from ws socket"
                raise FlowCloseError()
            else:
                fatal "read bytes less than wanted !"
                quit(1)

    except CatchableError as e:
        self.store.reuse move sv
        self.stop; raise e

proc start(self: WebsocketAdapter) =
    {.cast(raises: []).}:
        trace "starting"
        asyncSpawn keepAlive(self)


method signal*(self: WebsocketAdapter, dir: SigDirection, sig: Signals, chain: Chains = default) =
    if sig == start: self.start()

    if sig == close or sig == stop:
        self.stop()

    if sig == breakthrough: doAssert self.stopped, "break through signal while still running?"

    procCall signal(Tunnel(self), dir, sig, chain)
