import tunnel, strutils, stew/byteutils, threading/[channels], store
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

const
    GlobalTableSize = int(Cid.high) + 1
    CidHeaderLen = 2
    SizeHeaderLen = 2
    MuxHeaderLen = CidHeaderLen + SizeHeaderLen
    ConnectionChanFixedSize = 3


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


proc stop*(self: MuxAdapetr) =
    proc flush(chan: Chan, store: Store){.async.} =
        while true:
            {.cast(raises: []), gcsafe.}:
                var v = await chan.recv()
                if v == nil: chan.close(); chan.close(); break else: store.reuse v

    if not self.stopped:
        trace "stopping"
        self.stopped = true

        if not self.selectedCon.dcp.isNil:
            {.cast(raises: []).}:
                safeAccess:
                    notice "sent close channel signal ", cid = self.selectedCon.cid
                    asyncSpawn self.selectedCon.dcp.first.send nil
                    asyncSpawn flush(self.selectedCon.dcp.second, self.store)
                    system.reset(self.selectedCon)



        if not isNil(self.acceptConnectionFut): cancelSoon(self.acceptConnectionFut)
        if not isNil(self.readloopFut): cancelSoon(self.readloopFut)
        self.handles.apply do(x: Future[void]): cancelSoon x


proc closePacket(self: MuxAdapetr, cid: Cid): StringView =
    var sv = self.store.pop()
    sv.reserve(2)
    sv.write(0.uint16); sv.shiftl sizeof Cid
    sv.write(cid.Cid)
    return sv

proc handleCid(self: MuxAdapetr, cid: Cid, firstdata: StringView = nil) {.async.} =
    var sv: StringView = nil
    while not self.stopped:
        try:
            if firstdata.isNil:
                sv = await globalTable[cid].first.recv()
                if sv.isNil: raise newException(AsyncChannelError, "")
            else:
                sv = firstdata
        except AsyncChannelError as e:
            warn "HandleCid closed [Read]", msg = e.name, cid = cid
            {.cast(raises: []), gcsafe.}:
                var copy: Chan
                safeAccess:
                    globalTable[cid].first.close()
                    globalTable[cid].first.close()
                    copy = globalTable[cid].second
                    system.reset(globalTable[cid])
                asyncCheck copy.send nil

        except CancelledError as e:
            warn "HandleCid Canceled [Read]", msg = e.name, cid = cid
            # quit(1)
            asyncCheck muxSaveQueue.send (cid, nil)

        except CatchableError as e:
            error "HandleCid Unexpeceted Error, [Read]", name = e.name, msg = e.msg
            quit(1)

        try:
            if sv.isNil:
                trace "Sending close from", cid = cid
                await procCall write(Tunnel(self), closePacket(self, cid))
                return
            else:
                trace "Sending data from", cid = cid
                await procCall write(Tunnel(self), move sv)

        except [CancelledError, AsyncStreamError, TransportError, FlowError, WebSocketError]:
            var e = getCurrentException()
            error "HandleCid Canceled [Write] ", msg = e.name, cid = cid
            # no need to reuse non-nil sv because write have to
            if not self.stopped: signal(self, both, close)
            if not sv.isNil: asyncCheck muxSaveQueue.send (cid, sv)

            return
        except CatchableError as e:
            error "HandleCid error [Write]", name = e.name, msg = e.msg
            quit(1)



proc acceptcidloop(self: MuxAdapetr) {.async: (raw: true, raises: [CancelledError]).} =
    var retFut = newFuture[void](flags = {OwnCancelSchedule})

    proc register(cid: Cid, firstdata: StringView = nil) =
        assert(globalTableHas cid)
        var fut = self.handleCid(cid)
        self.handles.add fut
        fut.callback = proc(udata: pointer) =
            let index = self.handles.find fut
            if index != -1: self.handles.del index
        asyncSpawn fut

    proc restoration(){.async.} =
        while not self.stopped:
            var (cid, data) = await muxSaveQueue.recv()
            trace "acceptcidloop restored a cid", cid = cid
            register(cid, data)

    proc newRegisters(){.async.} =
        while not self.stopped:
            try:

                let new_cid = await self.masterChannel.recv()
                trace "acceptcidloop restored a cid", cid = new_cid
                register(new_cid, nil)
            except AsyncChannelError: # only means cancel !
                error "acceptcidloop [newRegisters] got AsyncChannelError!"
                if not self.stopped: signal(self, both, close)

    var restore_fut = restoration()
    var newregs_fut = newRegisters()

    retFut.callback = proc(udata: pointer) =
        trace "acceptcidloop finish"

    retFut.cancelCallback = proc(udata: pointer) =
        trace "acceptcidloop canceled"
        restore_fut.cancelSoon()
        newregs_fut.cancelSoon()
    return retFut

proc readloop(self: MuxAdapetr, whenNotFound: CidNotExistBehaviour){.async.} =
    #read data from right adapetr, send it to the right chan
    var data: StringView = nil
    assert not self.stopped

    try:
        while not self.stopped:
            #reads exactly MuxHeaderLen size
            var sv = await procCall read(Tunnel(self), MuxHeaderLen)
            var size: uint16 = 0
            var cid: uint16 = 0
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


            if globalTableHas(cid):
                try:
                    await globalTable[cid].second.send data
                    data = nil
                except AsyncChannelError:
                    # channel is half closed ...
                    self.store.reuse move data
                    warn "read loop was about to write data to a half closed chanenl!", cid = cid
                    await sleepAsync(5)
                    continue

            else:
                case whenNotFound:
                    of create:
                        if size == 0: self.store.reuse move data; continue # dont create a chan for a close sig!!!

                        notice "sending create!", cid = cid
                        self.masterChannel.sendSync cid
                        # 1 or 2 time moving to event loop must be much faster than waiting and also enough
                        await sleepAsync(1)
                        # await sleepAsync(1)
                        for i in 0 .. 100:
                            if globalTableHas cid:
                                safeAccess:
                                    await globalTable[cid].second.send move data
                                notice "data is written to created channel", cid = cid
                                await sleepAsync(1)
                                var fut = self.handleCid(cid)
                                self.handles.add fut
                                fut.callback = proc(udata: pointer) =
                                    let index = self.handles.find fut
                                    if index != -1: self.handles.del index
                                asyncSpawn fut
                                break

                                if i == 100:
                                    # This  never happen, so quit if that actually happend to catch bug
                                    fatal "The other thread did not handle a connection after 2 seconds of waiting !"
                                    quit(1)

                            await sleepAsync(20) # !

                    of sendclose:
                        if size > 0:
                            self.store.reuse move data
                            trace "sending close for", cid = cid
                            await procCall write(Tunnel(self), closePacket(self, cid))
                        else:
                            self.store.reuse move data
                    of nothing:
                        self.store.reuse move data


    except [CancelledError, AsyncChannelError, FlowError, TransportError]:
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



method init(self: MuxAdapetr, name: string, master: AsyncChannel[Cid], store: Store, loc: Location,
    cid: Cid) {.raises: [].} =
    self.location = loc
    self.store = store
    self.masterChannel = master
    self.selectedCon.cid = cid
    procCall init(Adapter(self), name, hsize = 0)



method start(self: MuxAdapetr){.raises: [].} =
    {.cast(raises: []).}:
        procCall start(Adapter(self))

        trace "starting"
        case self.location:
            of BeforeGfw:
                case self.side:
                    of Side.Left:
                        # left mode, we create and send our cid signal

                        let cid = when hasThreadSupport:
                            globalCounter.fetchAdd(1)
                            else:
                                globalCounter

                        when not hasThreadSupport: inc globalCounter

                        safeAccess:
                            globalTable[cid].first = newAsyncChannel[StringView](maxItems = ConnectionChanFixedSize)
                            globalTable[cid].second = newAsyncChannel[StringView](maxItems = ConnectionChanFixedSize)
                            globalTable[cid].first.open()
                            globalTable[cid].second.open()
                        self.selectedCon = (cid, addr globalTable[cid])
                        self.masterChannel.sendSync cid

                    of Side.Right:
                        # right side, we accept cid signals
                        self.acceptConnectionFut = acceptcidloop(self)
                        # we also need to read from right adapter
                        # examine and forward data to left channel
                        self.readloopFut = readloop(self, sendclose)
                        asyncSpawn self.acceptConnectionFut
                        asyncSpawn self.readloopFut

            of AfterGfw:
                case self.side:
                    of Side.Left:
                        # left mode, we have been created by right Mux
                        # we find our channels,write and read to it
                        doAssert(not globalTableHas self.selectedCon.cid)

                        safeAccess:
                            globalTable[self.selectedCon.cid].first = newAsyncChannel[StringView](maxItems = ConnectionChanFixedSize)
                            globalTable[self.selectedCon.cid].second = newAsyncChannel[StringView](maxItems = ConnectionChanFixedSize)
                            globalTable[self.selectedCon.cid].first.open()
                            globalTable[self.selectedCon.cid].second.open()

                            self.selectedCon.dcp = addr globalTable[self.selectedCon.cid]

                    of Side.Right:
                        # right side, we create cid signals
                        # self.acceptConnectionFut = acceptcidloop(self)
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
    debug "Write", size = rp.len
    if self.stopped: self.store.reuse rp; return

    try:
        case self.location:
            of BeforeGfw:
                case self.side:
                    of Side.Left:
                        var total_len = rp.len.uint16
                        rp.shiftl SizeHeaderLen
                        rp.write(total_len)
                        rp.shiftl CidHeaderLen
                        rp.write(self.selectedCon.cid)
                        await self.selectedCon.dcp.first.send(rp)

                    of Side.Right:
                        doAssert false, "this will not happen"


            of AfterGfw:
                case self.side:
                    of Side.Left:
                        var total_len = rp.len.uint16
                        rp.shiftl SizeHeaderLen
                        rp.write(total_len)
                        rp.shiftl CidHeaderLen
                        rp.write(self.selectedCon.cid)
                        await self.selectedCon.dcp.first.send(rp)
                    of Side.Right:
                        doAssert false, "this will not happen"


    except CatchableError as e:
        self.store.reuse(rp)
        self.stop; raise e

method read*(self: MuxAdapetr, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    try:
        case self.location:
            of BeforeGfw:
                case self.side:
                    of Side.Left:
                        if self.selectedCon.dcp.isNil:
                            raise newException(AsyncChannelError, message = "closed pipe")
                        var size: uint16 = 0
                        var cid: uint16 = 0
                        var sv = await self.selectedCon.dcp.second.recv()
                        copyMem(addr cid, sv.buf, sizeof(cid)); sv.shiftr sizeof(cid)
                        copyMem(addr size, sv.buf, sizeof(size)); sv.shiftr sizeof(size)
                        if not self.selectedCon.cid == cid:
                            fatal "cid mismatch", readcid = cid, wanted = self.selectedCon.cid
                            quit(1)
                        debug "read", bytes = size

                        if size.int < bytes:
                            trace "closing read channel.", size
                            self.store.reuse move sv
                            raise newException(CancelledError, message = "read close, size: " & $size)

                        return sv
                    of Side.Right:
                        doAssert false, "this will not happen"
            of AfterGfw:
                case self.side:
                    of Side.Left:
                        if self.selectedCon.dcp.isNil:
                            raise newException(AsyncChannelError, message = "closed pipe")
                        var size: uint16 = 0
                        var cid: uint16 = 0
                        var sv = await self.selectedCon.dcp.second.recv()
                        copyMem(addr cid, sv.buf, sizeof(cid)); sv.shiftr sizeof(cid)
                        copyMem(addr size, sv.buf, sizeof(size)); sv.shiftr sizeof(size)
                        if not self.selectedCon.cid == cid:
                            fatal "cid mismatch", readcid = cid, wanted = self.selectedCon.cid
                            quit(1)
                        debug "read", bytes = size

                        if size.int < bytes:
                            trace "closing read channel.", size
                            self.store.reuse move sv
                            raise newException(CancelledError, message = "read close, size: " & $size)

                        return sv

                    of Side.Right:
                        doAssert false, "this will not happen"



    except CatchableError as e:
        self.stop; raise e


method signal*(self: MuxAdapetr, dir: SigDirection, sig: Signals, chain: Chains = default) {.raises: [].} =
    if sig == breakthrough:
        if not self.stopped: fatal "break through signal while still running?"; quit(1)

    procCall signal(Tunnel(self), dir, sig, chain)

    if sig == close or sig == stop: self.stop()

    if sig == start: self.start()


proc staticInit() =
    logScope:
        section = "Global Memory"

    when hasThreadSupport: globalCounter.store(0) else: globalCounter = 0
    var total_size = sizeof(typeof(globalTable[][0])) * GlobalTableSize
    globalTable = cast[typeof globalTable](allocShared0(total_size))
    trace "Allocate globalTable", size = total_size
    static: doAssert sizeof(typeof(globalTable[][0])) <= 16, "roye google chromo sefid nakon plz !"

    if muxSaveQueue.isNil:
        muxSaveQueue = newAsyncChannel[tuple[c: Cid, d: StringView]]()

    trace "Initialized"

staticInit()
