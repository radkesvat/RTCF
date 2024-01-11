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
        socketw: WSSession
        socketr: WSSession
        store: Store
        onClose: CloseCb
        discardReadFut: Future[void]
        keepAliveFut: Future[void]

const writeTimeOut = 350.milliseconds
const pingInterval = 60.seconds


var readQueue = initDeque[StringView](initialSize = 4096)


proc prepareCloseBody(code: StatusCodes, reason: string): seq[byte] =
    result = reason.toBytes
    if ord(code) > 999:
        result = @(ord(code).uint16.toBytesBE()) & result


proc closeRead(socket: WSSession,store:Store){.async.} =
    if socket.readyState != ReadyState.Open:
        return
    await socket.send(prepareCloseBody(StatusFulfilled, ""), opcode = Opcode.Close)
    # read frames until closed
    try:
        while socket.readyState != ReadyState.Closed:
            var frame = await socket.readFrame()
            if frame.isNil: break
            var sv = store.pop()
            sv.reserve(frame.remainder.int)
            let read = await frame.read(socket.stream.reader, sv.buf, frame.remainder.int)
            if read == 0:
                store.reuse sv
                break
            echo "saved 1 frame ", sv.len
            readQueue.addLast sv

    except CancelledError as exc:
        raise exc
    except CatchableError as exc:
        discard # most likely EOF



proc stop*(self: WebsocketAdapter) =
    proc breakCycle(){.async.} =
        if not isNil(self.discardReadFut): await self.discardReadFut.cancelAndWait()
        if not isNil(self.keepAliveFut): await self.keepAliveFut.cancelAndWait()
        await self.socketw.close()

        await self.socketr.closeRead(self.store)

        await sleepAsync(5.seconds)
        self.signal(both, breakthrough)

    if not self.stopped:
        trace "stopping"
        self.stopped = true
        if not isNil(self.onClose): self.onClose()
        discard breakCycle()




proc discardRead(self: WebsocketAdapter){.async.} =
    var buf = allocShared(20)
    defer:
        deallocShared buf
    try:
        while not self.stopped: discard self.socketw.recv(buf, 20)
    except:
        discard



proc keepAlive(self: WebsocketAdapter){.async.} =
    while not self.stopped:
        try:
            await self.socketw.ping(@[1.byte])
            await self.socketr.ping(@[1.byte])
            await sleepAsync(pingInterval)

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
            var task = self.socketw.send(byteseq, Binary)
            var timeout = sleepAsync(writeTimeOut)
            if (await race(task, timeout)) == timeout:
                await task
                raise newException(AsyncTimeoutError, "write timed out")

            trace "written bytes to ws socket", bytes = byteseq.len
    except CatchableError as e:
        self.stop; raise e
    finally:
        self.store.reuse rp


method read*(self: WebsocketAdapter, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    var sv = self.store.pop()
    try:
        # trace "asking for ", bytes = bytes

        while true:
            if readQueue.len > 0:
                if not sv.isNil: self.store.reuse sv
                return readQueue.popFirst()
            # var bytesread = await self.socketr.recv(cast[ptr byte](sv.buf), bytes)
            var frame = await self.socketr.readFrame()
            if frame.isNil:raise FlowCloseError()
            sv.reserve(frame.remainder.int)
            let bytesread = await frame.read(self.socketr.stream.reader, sv.buf, frame.remainder.int)
            trace "received", bytes = bytesread
            if bytesread >= bytes:
                readQueue.addLast move sv
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
        self.keepAliveFut = keepAlive(self)


method signal*(self: WebsocketAdapter, dir: SigDirection, sig: Signals, chain: Chains = default) =
    if sig == start: self.start()

    if sig == close or sig == stop:
        self.stop()

    if sig == breakthrough: doAssert self.stopped, "break through signal while still running?"

    procCall signal(Tunnel(self), dir, sig, chain)
