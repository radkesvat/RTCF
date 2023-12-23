import tunnel,store, websock/websock



logScope:
    topic = "Websocket Adapter"


#     1    2    3    4    5    6    7 ...
# ---------------------------------------------------
#                 User Requets
# ---------------------------------------------------
#     Websocket contains variable lenght data      |
# ---------------------------------------------------


type
    WebsocketAdapter* = ref object of Adapter
        socket: WSSession
        store: Store

    
const
    bufferSize = 4096




method init(self: WebsocketAdapter, name: string, socket: WSSession, store: Store): WebsocketAdapter =
    self.socket = socket
    self.store = store
    procCall init(Adapter(self), name, hsize = 0)



proc new*(t: typedesc[WebsocketAdapter], name: string = "WebsocketAdapter", socket: WSSession, store: Store): WebsocketAdapter =
    result = new WebsocketAdapter
    result.init(name, socket, store)
    trace "Initialized new WebsocketAdapter", name


method write*(self: WebsocketAdapter, rp: StringView, chain: Chains = default): Future[void] {.async.} =
    defer:
        rp.reset()
        self.store.reuse rp

    rp.bytes(byteseq):
        await self.socket.send(byteseq,Binary)



method read*(self: WebsocketAdapter, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    var sv = self.store.pop()
    sv.reserve bytes
    var bytesread = await self.socket.recv(cast[ptr byte](sv.buf),bytes)

    if bytesread == bytes:
        return sv
    elif bytesread == 0:
        self.signal(both,close)
    else:
        error "read bytes less than wanted !"
        quit(1)


proc start(self: WebsocketAdapter) =
    {.cast(raises: []).}:

        discard

method signal*(self: WebsocketAdapter, dir: SigDirection, sig: Signals, chain: Chains = default) =
    var broadcast = false
    if sig == close or sig == stop:
        broadcast = not self.stopped
        self.stopped = true
        discard self.socket.close()

    if sig == start: self.start()
    if broadcast: procCall signal(Tunnel(self), dir, sig, chain)
    if sig == breakthrough: doAssert self.stopped, "break through signal while still running?"



