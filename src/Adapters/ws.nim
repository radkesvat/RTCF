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


proc stop*(self: WebsocketAdapter)=
    if not self.stopped :
        trace "stopping"
        self.stopped = true
        asyncSpawn self.socket.close()

method init(self: WebsocketAdapter, name: string, socket: WSSession, store: Store) =
    self.socket = socket
    self.store = store
    procCall init(Adapter(self), name, hsize = 0)



proc newWebsocketAdapter*(name: string = "WebsocketAdapter", socket: WSSession, store: Store): WebsocketAdapter =
    result = new WebsocketAdapter
    result.init(name, socket, store)
    trace "Initialized", name


method write*(self: WebsocketAdapter, rp: StringView, chain: Chains = default): Future[void] {.async.} =
    try:
        rp.bytes(byteseq):
            await self.socket.send(byteseq,Binary)

    except CatchableError as e:
        self.stop; raise e
    finally:
        self.store.reuse rp


method read*(self: WebsocketAdapter, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    var sv = self.store.pop()
    try:
        sv.reserve bytes
        var bytesread = await self.socket.recv(cast[ptr byte](sv.buf),bytes)

        if bytesread == bytes:
            return sv
        else:
            self.store.reuse sv
            if bytesread == 0:
                trace "received 0 bytes from ws socket"
                raise FlowCloseError()
            else:
                fatal "read bytes less than wanted !"
                quit(1)

    except CatchableError as e:
        self.stop; raise e

proc start(self: WebsocketAdapter) =
    {.cast(raises: []).}:
        trace "starting"
        

method signal*(self: WebsocketAdapter, dir: SigDirection, sig: Signals, chain: Chains = default) =
    if sig == start: self.start()

    if sig == close or sig == stop:
        self.stop()

    if sig == breakthrough: doAssert self.stopped, "break through signal while still running?"

    procCall signal(Tunnel(self), dir, sig, chain)
