import tunnel, strutils, threading/[channels], store
import sequtils, websock/types, std/locks
# This module unfortunately has global shared memory as part of its state

logScope:
    topic = "Mux Adapter"


#     1    2    3    4    5    6    7
# ----------------------------------
#   cid    |   size  |
# ----------------------------------
#         Mux       |
# ----------------------------------


type
    Cid* = uint16
    Chan = AsyncChannel[StringView]
    CidNotExistBehaviour = enum
        nothing, create, sendclose


    DualChan {.packed.} = object
        first: Chan
        second: Chan

    DualChanPtr = ptr DualChan


    MuxAdapetr* = ref object of Adapter
        acceptConnectionFut: Future[void]
        readloopFut: Future[void]
        selectedCon: tuple[cid: Cid, dcp: DualChanPtr]
        handles: seq[Future[void]]
        store: Store
        masterChannel: AsyncChannel[Cid]
        readChanFut: Future[StringView]
        writeChanFut: Future[void]


const
    GlobalTableSize = int(Cid.high) + 1
    CidHeaderLen = 2
    SizeHeaderLen = 2
    MuxHeaderLen = CidHeaderLen + SizeHeaderLen
    ConnectionChanFixedSizeW = 1
    ConnectionChanFixedSizeR = 8192


var globalTable: ptr UncheckedArray[DualChan]

when hasThreadSupport:
    import threading/atomics
    var globalCounter: Atomic[Cid]
    var globalLock: Lock
    initLock globalLock
else:
    var globalCounter: Cid

var muxSaveQueue: AsyncChannel[tuple[c: Cid, d: StringView]]



template safeAccess(body: untyped) =
    when hasThreadSupport:
        globalLock.acquire()
        try:
            body
        finally:
            globalLock.release()
    else:
        body


proc close(c: DualChan) = c.first.close(); c.second.close()
template close(c: DualChanPtr) = c[].close()

proc globalTableHas(id: Cid): bool =
    safeAccess:
        return not (isNil(globalTable[id].first) or isNil(globalTable[id].second))



proc closePacket(self: MuxAdapetr, cid: Cid): StringView =
    var sv = self.store.pop()
    sv.reserve(2)
    sv.write(0.uint16); sv.shiftl sizeof Cid
    sv.write(cid.Cid)
    return sv

proc stop*(self: MuxAdapetr, sendclose: bool = true) =
    proc doClose(fchan: Chan, schan: Chan, cid: Cid, store: Store, sc: bool){.async.} =
        {.cast(raises: []), gcsafe.}:
            if self.readChanFut != nil and not self.readChanFut.finished():
                await self.readChanFut.cancelAndWait()
            if self.writeChanFut != nil and not self.writeChanFut.finished():
                await self.writeChanFut.cancelAndWait()

            schan.close()
            schan.drain(proc(x: StringView) = (if x != nil: self.store.reuse x))

            if sc:
                await fchan.send(closePacket(self, cid))
            await fchan.send(nil, true)

    if not self.stopped:
        trace "stopping"
        self.stopped = true

        if not self.selectedCon.dcp.isNil:
            {.cast(raises: []).}:
                trace "sent close channel signal ", cid = self.selectedCon.cid
                var copy = self.selectedCon
                system.reset(self.selectedCon)
                asyncSpawn doClose(copy.dcp.first, copy.dcp.second,
                copy.cid, self.store, sendclose)

        if not isNil(self.acceptConnectionFut): cancelSoon(self.acceptConnectionFut)
        if not isNil(self.readloopFut): cancelSoon(self.readloopFut)
        self.handles.apply do(x: Future[void]): cancelSoon x




proc handleCid(self: MuxAdapetr, cid: Cid, firstdata_const: StringView = nil) {.async.} =
    var first_data = firstdata_const

    while true:
        var sv: StringView = nil
        try:
            if first_data.isNil:
                sv = await globalTable[cid].first.recv()
                if sv.isNil: raise newException(AsyncChannelError, "")
            else:
                sv = first_data; first_data = nil
        except AsyncChannelError as e:
            #read from closed channel, close will be sent,
            trace "HandleCid closed [Read]", msg = e.name, cid = cid

        except CancelledError as e:
            trace "HandleCid Canceled [Read]", msg = e.name, cid = cid
            if self.location == AfterGfw:
                discard globalTable[cid].second.send(closePacket(self, cid))

            notice "saving ", cid = cid
            muxSaveQueue.sendSync (cid, sv)

            return
        except CatchableError as e:
            error "HandleCid Unexpeceted Error, [Read]", name = e.name, msg = e.msg
            quit(1)

        try:
            if sv.isNil:
                {.cast(raises: []), gcsafe.}:
                    var copy: DualChan
                    safeAccess:
                        copy = globalTable[cid]
                        system.reset(globalTable[cid])
                    copy.first.close()
                    copy.first.close()
                    copy.second.drain(proc(x: StringView) = (if x != nil: self.store.reuse x))
                    copy.second.close()
                    return
            else:
                trace "Sending data from", cid = cid
                await procCall write(Tunnel(self), move sv)

        except [CancelledError, AsyncStreamError, TransportError, FlowError, WebSocketError]:
            var e = getCurrentException()
            error "HandleCid Canceled [Write] ", msg = e.name, cid = cid

            # no need to reuse non-nil sv because write have to
            if self.location == AfterGfw:
                discard globalTable[cid].second.send(closePacket(self, cid))
            notice "saving ", cid = cid
            muxSaveQueue.sendSync (cid, sv)

            if not self.stopped: signal(self, both, close)
            return
        except CatchableError as e:
            error "HandleCid error [Write]", name = e.name, msg = e.msg
            quit(1)



proc register(self: MuxAdapetr,cid: Cid, firstdata: StringView = nil) =
        var fut = self.handleCid(cid, firstdata)
        self.handles.add fut
        fut.callback = proc(udata: pointer) =
            let index = self.handles.find fut
            if index != -1: self.handles.del index
        asyncSpawn fut

proc restore(self: MuxAdapetr) =
    while muxSaveQueue.dataLeft() > 0:
        try:
            var (cid, data) =  muxSaveQueue.recvSync()
            notice "Restored", cid = cid
            self.register(cid, data)
        except:
            var e = getCurrentException()
            error "Restore error !", msg = e.name, msg = e.msg

proc acceptcidloop(self: MuxAdapetr) {.async.} =
    while not self.stopped:
        try:
            let new_cid = await self.masterChannel.recv()
            trace "acceptcidloop got a cid", cid = new_cid
            self.register(new_cid, nil)
        except AsyncChannelError: # only means cancel !
            error "acceptcidloop [newRegisters] got AsyncChannelError!"
            if not self.stopped: signal(self, both, close)


proc readloop(self: MuxAdapetr, whenNotFound: CidNotExistBehaviour){.async.} =
    #read data from right adapetr, send it to the right chan
    var data: StringView = nil
    # assert not self.stopped
    try:
        while not self.stopped:
            #reads exactly MuxHeaderLen size
            var sv = await procCall read(Tunnel(self), MuxHeaderLen)
            var size: uint16 = 0
            var cid: Cid = 0
            copyMem(addr cid, sv.buf, sizeof(cid)); sv.shiftr sizeof(cid)
            copyMem(addr size, sv.buf, sizeof(size)); sv.shiftr sizeof(size)

            data = if size > 0:
                    var rse = await procCall read(Tunnel(self), size.int)
                    sv.shiftl sizeof(size)
                    rse.shiftl sizeof(size); copyMem(rse.buf, sv.buf, sizeof(size))
                    sv.shiftl sizeof(cid)
                    rse.shiftl sizeof(cid); copyMem(rse.buf, sv.buf, sizeof(cid))
                    self.store.reuse move sv
                    rse
                else:
                    sv.shiftl MuxHeaderLen; sv




            safeAccess:
                if not (isNil(globalTable[cid].first) or isNil(globalTable[cid].second)):
                    try:
                        if not (globalTable[cid].second.trySend(data)):
                            self.store.reuse move data
                            discard globalTable[cid].first.send(closePacket(self, cid))
                        data = nil; continue
                    except AsyncChannelError as e:
                        # channel is half closed ...
                        self.store.reuse move data
                        warn "read loop was about to write data to a half closed chanenl!", msg = e.msg, cid = cid
                        continue


            if size == 0: self.store.reuse move data; continue # dont do anything

            case whenNotFound:
                of create:
                    # echo "make:      ",cid
                    trace "creating left channels", cid = cid
                    safeAccess:
                        globalTable[cid].first = newAsyncChannel[StringView](maxItems = ConnectionChanFixedSizeW)
                        globalTable[cid].second = newAsyncChannel[StringView](maxItems = ConnectionChanFixedSizeR)
                        globalTable[cid].first.open()
                        globalTable[cid].second.open()
                    trace "data is written to created channel", cid = cid
                    var fut = self.handleCid(cid)
                    self.handles.add fut
                    fut.callback = proc(udata: pointer) =
                        let index = self.handles.find fut
                        if index != -1: self.handles.del index
                    asyncSpawn fut
                    await globalTable[cid].second.send move data
                    self.masterChannel.sendSync cid
                of sendclose:
                    if size > 0:
                        self.store.reuse move data
                        # trace "sending close for", cid = cid
                        # # echo "close-back:  ",cid
                        # await procCall write(Tunnel(self), closePacket(self, cid))
                    else:
                        self.store.reuse move data
                of nothing:
                    self.store.reuse move data


    except [CancelledError, AsyncChannelError, WSClosedError, FlowError, TransportError]:
        var e = getCurrentException()
        trace "Readloop canceled", name = e.name, msg = e.msg
    except AsyncStreamError as e:
        error "Readloop canceled (when reading from ws)", name = e.name, msg = e.msg
    except CatchableError as e:
        error "Readloop Unexpected Error", name = e.name, msg = e.msg
        quit(1)
    finally:
        if data != nil: self.store.reuse data
        if not self.stopped: signal(self, both, close)



proc init(self: MuxAdapetr, name: string, master: AsyncChannel[Cid], store: Store, loc: Location,
    cid: Cid) {.raises: [].} =
    self.location = loc
    self.store = store
    self.masterChannel = master
    self.selectedCon.cid = cid
    procCall init(Adapter(self), name, hsize = 0)



method start(self: MuxAdapetr){.raises: [].} =
    proc newCid(): Cid =
        while true:
            let res = when hasThreadSupport:
                    globalCounter.fetchAdd(1)
                else:
                    globalCounter
            when not hasThreadSupport: inc globalCounter

            if not globalTableHas(res):
                return res



    {.cast(raises: []).}:
        procCall start(Adapter(self))
        trace "starting"
        case self.location:
            of BeforeGfw:
                case self.side:
                    of Side.Left:
                        # left mode, we create and send our cid signal
                        let cid = newCid()

                        safeAccess:
                            globalTable[cid].first = newAsyncChannel[StringView](maxItems = ConnectionChanFixedSizeW)
                            globalTable[cid].second = newAsyncChannel[StringView](maxItems = ConnectionChanFixedSizeR)
                            globalTable[cid].first.open()
                            globalTable[cid].second.open()

                        self.selectedCon = (cid, addr globalTable[cid])
                        self.masterChannel.sendSync cid

                    of Side.Right:
                        self.restore()
                        # right side, we accept cid signals
                        self.acceptConnectionFut = acceptcidloop(self)
                        # we also need to read from right adapter
                        # examine and forward data to left channel
                        self.readloopFut = readloop(self, sendclose)
                        # asyncSpawn self.acceptConnectionFut
                        asyncSpawn self.readloopFut

            of AfterGfw:
                case self.side:
                    of Side.Left:
                        # left mode, we have been created by right Mux
                        # we find our channels,write and read to it
                        doAssert(globalTableHas self.selectedCon.cid)
                        self.selectedCon.dcp = addr globalTable[self.selectedCon.cid]

                    of Side.Right:
                        # right side, we create cid signals
                        self.restore()
                        # we also need to read from right adapter
                        # examine and forward data to left channel
                        self.readloopFut = readloop(self, create)
                        # asyncSpawn self.acceptConnectionFut
                        asyncSpawn self.readloopFut


proc newMuxAdapetr*(name: string = "MuxAdapetr", master: AsyncChannel[Cid], store: Store, loc: Location,
    cid: Cid = 0): MuxAdapetr {.raises: [].} =
    result = new MuxAdapetr
    result.init(name, master, store, loc, cid)
    trace "Initialized new MuxAdapetr", name


method write*(self: MuxAdapetr, rp: StringView, chain: Chains = default): Future[void] {.async.} =
    if self.stopped: self.store.reuse rp; raise newException(AsyncChannelError, message = "closed pipe")
    debug "Write", size = rp.len


    when not defined(release):
        case self.location:
            of BeforeGfw:
                case self.side:
                    of Side.Left: discard
                    of Side.Right:
                        doAssert false, "this must not happen"
            of AfterGfw:
                case self.side:
                    of Side.Left: discard
                    of Side.Right:
                        doAssert false, "this must not happen"

    try:
        var total_len = rp.len.uint16
        rp.shiftl SizeHeaderLen
        rp.write(total_len)
        rp.shiftl CidHeaderLen
        rp.write(self.selectedCon.cid)
        self.writeChanFut = self.selectedCon.dcp.first.send(rp)
        await self.writeChanFut


    except CatchableError as e:
        self.store.reuse(rp)
        self.stop(); raise e


method read*(self: MuxAdapetr, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    if self.stopped: raise newException(AsyncChannelError, message = "closed pipe")

    when not defined(release):
        case self.location:
            of BeforeGfw:
                case self.side:
                    of Side.Left: discard

                    of Side.Right:
                        doAssert false, "this must not happen"
            of AfterGfw:
                case self.side:
                    of Side.Left: discard

                    of Side.Right:
                        doAssert false, "this must not happen"
    try:

        if self.selectedCon.dcp.isNil:
            raise newException(AsyncChannelError, message = "closed pipe")
        var size: uint16 = 0
        var cid: uint16 = 0
        self.readChanFut = self.selectedCon.dcp.second.recv()
        var sv = await self.readChanFut
        assert sv != nil
        copyMem(addr cid, sv.buf, sizeof(cid)); sv.shiftr sizeof(cid)
        copyMem(addr size, sv.buf, sizeof(size)); sv.shiftr sizeof(size)

        if self.stopped:
            self.store.reuse sv
            raise newException(AsyncChannelError, message = "closed pipe")

        if self.selectedCon.cid != cid:
            fatal "cid mismatch!", c1 = self.selectedCon.cid, c2 = cid; quit(1)

        debug "read", bytes = size

        if size.int < bytes:
            trace "closing read channel.", size
            self.store.reuse move sv
            self.stop(false)
            raise newException(CancelledError, message = "read close, size: " & $size)

        return sv


    except CatchableError as e:
        self.stop(); raise e


method signal*(self: MuxAdapetr, dir: SigDirection, sig: Signals, chain: Chains = default) {.raises: [].} =
    if sig == breakthrough:
        if not self.stopped: fatal "break through signal while still running?"; quit(1)


    if sig == close or sig == stop: self.stop()
    procCall signal(Tunnel(self), dir, sig, chain)

    if sig == start: self.start()


proc staticInit() =
    logScope:
        section = "Global Memory"

    when hasThreadSupport: globalCounter.store(0) else: globalCounter = 0
    var total_size = sizeof(typeof(globalTable[][0])) * GlobalTableSize
    globalTable = cast[typeof globalTable](allocShared0(total_size))
    trace "Allocate globalTable", size = total_size
    static: doAssert sizeof(typeof(globalTable[][0])) <= 16, "roye google chromo sefid nakon plz !"

    muxSaveQueue = newAsyncChannel[tuple[c: Cid, d: StringView]]()
    muxSaveQueue.open()

    trace "Initialized"

staticInit()
