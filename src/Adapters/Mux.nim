import tunnel, strutils, stew/byteutils, threading/[channels, atomics], store
import sequtils
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
    Cid = uint16
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
        buffered: seq[StringView]
        handles: seq[Future[void]]
        store: Store
        masterChannel: AsyncChannel[Cid]

const
    GlobalTableSize = int(Cid.high) + 1
    CidHeaderLen = 2
    SizeHeaderLen = 2
    MuxHeaderLen = CidHeaderLen + SizeHeaderLen


var globalTable: ptr UncheckedArray[DualChan]
var globalCounter: Atomic[Cid]

proc close(c: DualChanPtr) = c.first.close(); c.second.close()

template globalTableHas(id: Cid): bool = (isNil(globalTable[id].first) or isNil(globalTable[id].second))

template safeCancel(body: untyped) =
    try:
        body
    except CancelledError as e:
        if not self.stopped: raise e

proc handleCid(self: MuxAdapetr, cid: Cid) {.async.} =
    try:
        while not self.stopped:
            var sv = await globalTable[cid].first.recv()
            self.buffered.add sv

    except CancelledError as e:
        trace "handleCid ended with CancelledError"
    except CatchableError as e:
        trace "handleCid ended with Non CancelledError", etype = e.name
        self.masterChannel.sendSync cid


proc acceptcidloop(self: MuxAdapetr){.async.} =
    safeCancel:
        while not self.stopped:
            let new_cid = await self.masterChannel.recv()
            assert(globalTableHas new_cid)
            try:
                self.handles.add self.handleCid(new_cid)
            except CatchableError as e:
                trace "sending close for", cid = new_cid, msg = e.msg
                var sv = self.store.pop()
                sv.write(0.uint16); sv.shiftl sizeof uint16
                sv.write(new_cid.Cid); sv.shiftl sizeof Cid
                await procCall write(Tunnel(self), sv)



# called when we are on the right side
proc readloop(self: MuxAdapetr, whenNotFound: CidNotExistBehaviour){.async.} =
    #read data from right adapetr, send it to the right chan
    safeCancel:
        while not self.stopped:
            #reads exactly MuxHeaderLen size
            var sv = await procCall read(Tunnel(self), MuxHeaderLen)
            var size: uint16 = 0
            var cid: uint16 = 0
            copyMem(addr cid, sv.buf, sizeof(cid)); sv.shiftr sizeof(cid)
            copyMem(addr size, sv.buf, sizeof(size)); sv.shiftr sizeof(size)
            var data = if size > 0:
                    var res = await procCall read(Tunnel(self), size.int)
                    res.shiftr MuxHeaderLen; copyMem(res.buf, sv.buf, MuxHeaderLen)
                    res.shiftl MuxHeaderLen; res
                else:
                    sv.shiftl MuxHeaderLen; sv

            if globalTableHas(cid):
                await globalTable[cid].second.send data
            else:
                case whenNotFound:
                    of create:
                        self.masterChannel.sendSync cid
                        # 1 or 2 time moving to event loop must be much faster than waiting and also enough
                        await sleepAsync(1)
                        # await sleepAsync(1)
                        for i in 0 .. 100:
                            if globalTableHas cid:
                                await globalTable[cid].second.send data
                                return
                            await sleepAsync(20)
                        # This  never happen, so quit if that actually happend to catch bug
                        quit("The other thread did not handle a connection after 2 seconds of waiting !")

                    of sendclose:
                        data.shiftl sizeof(size)
                        data.write(typeof(size)(0))
                        sv.shiftr sizeof(size)
                        data.setLen MuxHeaderLen
                        await procCall write(Tunnel(self), data)
                    of nothing: discard




method init(self: MuxAdapetr, name: string, master: AsyncChannel[Cid], store: Store, loc: Location,
    cid: Cid): MuxAdapetr =
    self.location = loc
    self.store = store
    self.masterChannel = master
    self.selectedCon.cid = cid
    procCall init(Adapter(self), name, hsize = 0)


proc start(self: MuxAdapetr) =
    {.cast(raises: []).}:
        case self.location:
            of BeforeGfw:
                case self.side:
                    of Side.Left:
                        # left mode, we create and send our cid signal
                        let cid = globalCounter.fetchAdd(1)
                        globalTable[cid].first = newAsyncChannel[StringView](maxItems = 16)
                        globalTable[cid].second = newAsyncChannel[StringView](maxItems = 16)

                        self.selectedCon = (cid, addr globalTable[cid])
                        self.masterChannel.sendSync cid

                    of Side.Right:
                        # right side, we accept cid signals
                        self.acceptConnectionFut = acceptcidloop(self)
                        # we also need to read from right adapter
                        # examine and forward data to left channel
                        self.readloopFut = readloop(self, sendclose)

            of AfterGfw:
                case self.side:
                    of Side.Left:
                        # left side, we create cid signals
                        self.acceptConnectionFut = acceptcidloop(self)
                        # we also need to read from left adapter
                        # examine and forward data to right channel
                        self.readloopFut = readloop(self, create)

                    of Side.Right:
                        # right mode, we have been created by left Mux
                        # we find our channels,write and read to it
                        doAssert(self.selectedCon.cid != 0)
                        doAssert(not globalTableHas self.selectedCon.cid)
                        globalTable[self.selectedCon.cid].first = newAsyncChannel[StringView](maxItems = 16)
                        globalTable[self.selectedCon.cid].second = newAsyncChannel[StringView](maxItems = 16)

                        self.selectedCon.dcp = addr globalTable[self.selectedCon.cid]


proc new*(t: typedesc[MuxAdapetr], name: string = "MuxAdapetr", master: AsyncChannel[Cid], store: Store, loc: Location,
    cid: Cid = 0): MuxAdapetr =
    result = new MuxAdapetr
    result.init(name, master, store, loc, cid)
    trace "Initialized new MuxAdapetr", name


method write*(self: MuxAdapetr, rp: StringView, chain: Chains = default): Future[void] {.async.} =
    debug "Write", adaptername = self.name, size = rp.len

    case self.location:
        of BeforeGfw:
            case self.side:
                of Side.Left:
                    rp.shiftl SizeHeaderLen
                    rp.write(rp.len.uint16)
                    rp.shiftl CidHeaderLen
                    rp.write(self.selectedCon.cid)
                    await self.selectedCon.dcp.first.send(rp)

                of Side.Right:
                    doAssert false, "this will not happen"


        of AfterGfw:
            case self.side:
                of Side.Left:
                    doAssert false, "this will not happen"
                    #this will not happen
                of Side.Right:
                    rp.shiftl SizeHeaderLen
                    rp.write(rp.len.uint16)
                    rp.shiftl CidHeaderLen
                    rp.write(self.selectedCon.cid)
                    await self.selectedCon.dcp.first.send(rp)


method read*(self: MuxAdapetr, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    info "read", adaptername = self.name
    case self.location:
        of BeforeGfw:
            case self.side:
                of Side.Left:
                    var size: uint16 = 0
                    var cid: uint16 = 0
                    var sv = await self.selectedCon.dcp.second.recv()
                    copyMem(addr cid, sv.buf, sizeof(cid)); sv.shiftr sizeof(cid)
                    copyMem(addr size, sv.buf, sizeof(size)); sv.shiftr sizeof(size)
                    assert self.selectedCon.cid == cid # ofcourse!
                    assert size.int == sv.len # full packet must be received here
                    if size.int > bytes:
                        trace "closing read channel.", size
                        raise newException(CancelledError,message= "read close, size: " & $size)


                    return sv
                of Side.Right:
                    doAssert false, "this will not happen"
        of AfterGfw:
            case self.side:
                of Side.Left:
                    doAssert false, "this will not happen"
                of Side.Right:
                    var size: uint16 = 0
                    var cid: uint16 = 0
                    var sv = await self.selectedCon.dcp.second.recv()
                    copyMem(addr cid, sv.buf, sizeof(cid)); sv.shiftr sizeof(cid)
                    copyMem(addr size, sv.buf, sizeof(size)); sv.shiftr sizeof(size)
                    assert self.selectedCon.cid == cid # ofcourse!
                    assert size.int == sv.len # full packet must be received here
                    if size.int > bytes:
                        trace "closing read channel.", size
                        raise newException(CancelledError,message= "read close, size: " & $size)

                    return sv

method signal*(self: MuxAdapetr, dir: SigDirection, sig: Signals, chain: Chains = default) =
    if sig == close or sig == stop: self.stopped = true
    if sig == start: self.start()


    if sig == close or sig == stop:
        self.stopped = true
        if self.selectedCon.cid != 0:
            close(self.selectedCon.dcp)
        if not isNil(self.acceptConnectionFut): cancelSoon(self.acceptConnectionFut)
        if not isNil(self.readloopFut): cancelSoon(self.readloopFut)
        self.handles.apply do(x: Future[void]): cancelSoon x

    
    procCall signal(Tunnel(self), dir, sig, chain)

    if sig == breakthrough: doAssert self.stopped, "break through signal while still running?"




proc staticInit() =
    logScope:
        section = "Global Memory"

    globalCounter.store(0)
    var total_size = sizeof(typeof(globalTable[][0])) * GlobalTableSize
    globalTable = cast[typeof globalTable](allocShared0(total_size))
    trace "Allocate globalTable", size = total_size
    static: doAssert sizeof(typeof(globalTable[][0])) <= 16, "roye google chromo sefid nakon plz !"
    trace "Initialized"

staticInit()
