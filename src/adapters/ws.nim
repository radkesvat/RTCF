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
        readFut: Future[int]
        writeFut: Future[void]

        finished: AsyncEvent

const writeTimeOut = 1800.milliseconds
const pingInterval = 60.seconds


var readQueue = initDeque[StringView](initialSize = 4096)



proc prepareCloseBody(code: StatusCodes, reason: string): seq[byte] =
    result = reason.toBytes
    if ord(code) > 999:
        result = @(ord(code).uint16.toBytesBE()) & result


proc closeRead(socket: WSSession, store: Store, finish: AsyncEvent){.async.} =
    defer: finish.fire()

    if socket.readyState != ReadyState.Open:
        return
    # read frames until closed
    var sv: StringView = nil
    try:
        socket.readyState = ReadyState.Closing

        # await socket.send(prepareCloseBody(StatusFulfilled, ""), opcode = Opcode.Close)

        while socket.readyState != ReadyState.Closed:
            var size: uint16 = 0

            var size_header_read = await socket.recv(cast[ptr byte](addr size), 2)
            if size_header_read != 2: raise FlowCloseError()
            sv = store.pop()
            sv.reserve size.int
            var payload_size = await socket.recv(cast[ptr byte](sv.buf), size.int)
            if payload_size == 0: raise FlowCloseError()

            trace "received", bytes = payload_size
            echo "saved 1 packet"
            readQueue.addLast move sv

            # var frame = await socket.readFrame()
            # if frame.isNil: break
            # socket.binary = frame.opcode == Opcode.Binary
            # var sv = store.pop()
            # sv.reserve(frame.remainder.int)
            # let read = await frame.read(socket.stream.reader, sv.buf, frame.remainder.int)
            # if read == 0:
            #     store.reuse sv
            #     break
            # echo "saved 1 frame ", sv.len
            # readQueue.addLast sv

    except CancelledError as exc:
        raise exc
    except CatchableError as exc:
        discard # most likely EOF
    finally:
        if not sv.isNil: store.reuse sv



proc stop*(self: WebsocketAdapter) =
    proc breakCycle(){.async.} =
        if not isNil(self.keepAliveFut): await self.keepAliveFut.cancelAndWait()

        if self.writeFut != nil and not self.writeFut.completed():
            try:
                await self.writeFut.wait(2.seconds)
            except:
                discard

        var wc = self.socketw.close()

        var lastchance = false
        while true:
            if self.readFut != nil and not self.readFut.completed():
                if not lastchance: lastchance = true; await sleepAsync(1000)
                else:
                    try:
                        await self.readFut.cancelAndWait()
                        break
                    except:
                        discard
            else: break
                

        await wc 
        await self.socketr.closeRead(self.store, self.finished)
        # echo "1"
        # await self.writeCompleteEv.wait()
        # echo "2"
        # await self.socketw.close()

        # echo "3"
        # try:
        #     await self.readCompleteEv.wait().wait(3.seconds)
        # except: discard
        # echo "4"

        # try:
        #     await self.socketr.closeRead(self.store, self.finished).wait(3.seconds)
        # except: discard
        # echo "5"


        # if not isNil(self.discardReadFut): await self.discardReadFut.cancelAndWait()


        # await self.socketr.close()
        await sleepAsync(5.seconds)

        # await self.socketw.close() and self.socketr.close()
        # await self.socketr.close()
        # let cr = self.socketr.closeRead(self.store)
        # await self.socketw.close()
        # await cr

        self.signal(both, breakthrough)

    if not self.stopped:
        trace "stopping"
        self.stopped = true
        self.finished.clear()
        if not isNil(self.onClose): self.onClose()
        asyncSpawn breakCycle()




# proc discardRead(self: WebsocketAdapter){.async.} =
#     var buf = allocShared(20)
#     defer:
#         deallocShared buf
#     try:
#         while not self.stopped: discard self.socketw.recv(buf, 20)
#     except:
#         discard



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
    # self.writeCompleteEv = newAsyncEvent()
    # self.readCompleteEv = newAsyncEvent()
    self.finished = newAsyncEvent()
    self.finished.fire()
    # self.discardReadFut = discardRead(self)

proc newWebsocketAdapter*(name: string = "WebsocketAdapter", socketr: WSSession, socketw: WSSession, store: Store,
        onClose: CloseCb): WebsocketAdapter {.raises: [].} =
    result = new WebsocketAdapter
    result.init(name, socketr, socketw, store, onClose)
    trace "Initialized", name



method write*(self: WebsocketAdapter, rp: StringView, chain: Chains = default): Future[void] {.async.} =

    try:
        if self.stopped: raise FlowCloseError()
        # self.writeCompleteEv.clear()

        # if not self.finished.isSet:
        #     await self.finished.wait()
        #     raise FlowCloseError


        var size: uint16 = rp.len.uint16
        rp.shiftl 2
        rp.write(size)
        rp.bytes(byteseq):
            self.writeFut = self.socketw.send(byteseq, Binary)
            var timeout = sleepAsync(writeTimeOut)
            if (await race(self.writeFut, timeout)) == timeout:
                await self.writeFut
                self.store.reuse rp
                raise newException(AsyncTimeoutError, "write timed out")
            else:
                timeout.cancelSoon()
                self.store.reuse rp


            # await self.socketw.send(byteseq, Binary).wait(writeTimeOut)

            trace "written bytes to ws socket", bytes = byteseq.len
    except CatchableError as e:
        self.stop()
        if not self.finished.isSet():
            # self.writeCompleteEv.fire()
            await self.finished.wait()
        raise e

    # finally:
    #     self.writeCompleteEv.fire()



method read*(self: WebsocketAdapter, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    var sv = self.store.pop()
    var size: uint16 = 0
    try:
        if self.stopped: raise FlowCloseError()
        # self.readCompleteEv.clear()

        trace "asking for ", bytes = bytes

        while true:
            if readQueue.len > 0:
                if not sv.isNil: self.store.reuse sv
                return readQueue.popFirst()

            self.readFut = self.socketr.recv(cast[ptr byte](addr size), 2)
            var size_header_read = await self.readFut 
            if size_header_read != 2: raise FlowCloseError()

            sv.reserve size.int
            var payload_size = await self.socketr.recv(cast[ptr byte](sv.buf), size.int)
            if payload_size == 0: raise FlowCloseError()

            trace "received ", bytes = payload_size
            readQueue.addLast move sv
        # while true:
        #     if readQueue.len > 0:
        #         if not sv.isNil: self.store.reuse sv
        #         return readQueue.popFirst()

        #     # var bytesread = await self.socketr.recv(cast[ptr byte](sv.buf), bytes)
        #     var frame = await self.socketr.readFrame(self.socketr.extensions)
        #     if frame.isNil:
        #         assert self.socketr.readyState == ReadyState.Closed
        #         raise FlowCloseError()

        #     self.socketr.binary = frame.opcode == Opcode.Binary
        #     sv.reserve(frame.remainder.int)
        #     let bytesread = await frame.read(self.socketr.stream.reader, sv.buf, frame.remainder.int)
        #     trace "received", bytes = bytesread

        #     if bytesread >= bytes:
        #         readQueue.addLast move sv
        #     else:
        #         if bytesread == 0:
        #             trace "received 0 bytes from ws socket"
        #             raise FlowCloseError()
        #         else:
        #             fatal "read bytes less than wanted !"
        #             quit(1)

    except CatchableError as e:
        self.store.reuse move sv
        self.stop()
        if not self.finished.isSet():
            # self.readCompleteEv.fire()
            await self.finished.wait()
        raise e
    # finally:
    #     self.readCompleteEv.fire()


proc start(self: WebsocketAdapter) =
    {.cast(raises: []).}:
        trace "starting"
        # self.keepAliveFut = keepAlive(self)


method signal*(self: WebsocketAdapter, dir: SigDirection, sig: Signals, chain: Chains = default) =
    if sig == start: self.start()

    if sig == close or sig == stop:
        self.stop()

    if sig == breakthrough: doAssert self.stopped, "break through signal while still running?"

    procCall signal(Tunnel(self), dir, sig, chain)
