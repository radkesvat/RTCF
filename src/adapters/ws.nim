import tunnel, store, deques, websock/websock
import stew/endians2


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
        socket: WSSession
        store: Store
        onClose: CloseCb
        discardReadFut: Future[void]
        keepAliveFut: Future[void]
        readFut: Future[int]
        writeFut: Future[void]
        finished: AsyncEvent
        writeClosed: bool

const writeTimeOut = 900.milliseconds
const pingInterval = 60.seconds
const closeMagic: uint16 = 0xFFFF




proc prepareCloseBody(code: StatusCodes, reason: string): seq[byte] =
    result = reason.toBytes
    if ord(code) > 999:
        result = @(ord(code).uint16.toBytesBE()) & result


proc stop*(self: WebsocketAdapter) =
    proc breakCycle(){.async.} =
    #     if not isNil(self.keepAliveFut): await self.keepAliveFut.cancelAndWait()

        if self.writeFut != nil and not self.writeFut.completed():
            try:
                await self.writeFut
            except:
                discard
        await self.socket.stream.closeWait()
        await sleepAsync(5.seconds)
        self.signal(both, breakthrough)

    if not self.stopped:
        trace "stopping"
        self.stopped = true
        if not isNil(self.onClose): self.onClose()
        asyncSpawn breakCycle()



template stopByWrite(self: WebsocketAdapter) =
    if not self.writeClosed:
        self.writeClosed = true
        try:
            await self.socket.send(@(closeMagic.toBytesBE), Binary)
        except:
            discard

    await self.finished.wait()

proc stopByRead(self: WebsocketAdapter) =
    self.finished.fire()
    self.stop()

# proc discardRead(self: WebsocketAdapter){.async.} =
#     var buf = allocShared(20)
#     defer:
#         deallocShared buf
#     try:
#         while not self.stopped: discard self.socket.recv(buf, 20)
#     except:
#         discard



proc keepAlive(self: WebsocketAdapter){.async.} =
    while not self.stopped:
        try:
            await self.socket.ping(@[1.byte])
            await self.socket.ping(@[1.byte])
            await sleepAsync(pingInterval)

        except:
            error "Failed to ping socket"
            self.stop()



proc init(self: WebsocketAdapter, name: string, socket: WSSession, store: Store, onClose: CloseCb) {.raises: [].} =
    procCall init(Adapter(self), name, hsize = 0)
    self.socket = socket
    self.store = store
    self.onClose = onClose
    self.finished = newAsyncEvent()
    self.finished.clear()

proc newWebsocketAdapter*(name: string = "WebsocketAdapter", socket: WSSession, store: Store,
        onClose: CloseCb): WebsocketAdapter {.raises: [].} =
    result = new WebsocketAdapter
    result.init(name, socket, store, onClose)
    trace "Initialized", name



method write*(self: WebsocketAdapter, rp: StringView, chain: Chains = default): Future[void] {.async.} =
    try:
        if self.writeClosed or self.stopped: raise FlowCloseError()
        var size: uint16 = rp.len.uint16
        rp.shiftl 2
        rp.write(size)
        rp.bytes(byteseq):
            self.writeFut = self.socket.send(byteseq, Binary)
            var timeout = sleepAsync(writeTimeOut)
            if (await race(self.writeFut, timeout)) == timeout:
                signal(self, both, pause)
                await self.writeFut
                self.store.reuse rp
                raise newException(AsyncTimeoutError, "write timed out")
            else:
                self.store.reuse rp
                timeout.cancelSoon()

            trace "written bytes to ws socket", bytes = byteseq.len
    except CatchableError as e:
        self.stopByWrite()
        raise e




method read*(self: WebsocketAdapter, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    var sv = self.store.pop()
    var size: uint16 = 0
    try:
        if self.stopped: raise FlowCloseError()

        trace "asking for ", bytes = bytes

        while true:
            self.readFut = self.socket.recv(cast[ptr byte](addr size), 2)
            var size_header_read = await self.readFut
            if size_header_read != 2: raise FlowCloseError()

            if size == closeMagic: raise FlowCloseError()

            sv.reserve size.int
            var payload_size = await self.socket.recv(cast[ptr byte](sv.buf), size.int)
            if payload_size < size.int: raise FlowCloseError()

            trace "received ", bytes = payload_size
            return sv

    except CatchableError as e:
        if not sv.isNil: self.store.reuse sv
        self.stopByRead()
        raise e


proc start(self: WebsocketAdapter) =
    {.cast(raises: []).}:
        trace "starting"


method signal*(self: WebsocketAdapter, dir: SigDirection, sig: Signals, chain: Chains = default) =
    if sig == start: self.start()

    if sig == close or sig == stop:
        self.stop()

    if sig == breakthrough: doAssert self.stopped, "break through signal while still running?"

    procCall signal(Tunnel(self), dir, sig, chain)
