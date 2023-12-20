import tunnel, strutils, stew/byteutils, threading/[channels, atomics], store
import sequtils

# This module unfortunately has global shared memory as part of its state

logScope:
    topic = "Mux Adapter"


const
    GlobalTableSize = int(uint16.high) + 1
    MuxHeaderLen = 5

type
    Chan = AsyncChannel[StringView]

    DualChan {.packed.} = object
        first: Chan
        second: Chan

    DualChanPtr = ptr DualChan



    MuxAdapetr* = ref object of Adapter

        selectedCon: tuple[cid: int, dcp: DualChanPtr]

        buffered: seq[StringView]
        dataAvailable: AsyncEvent
        acceptInputFuture: Future[void]
        handles: seq[Future[void]]
        store: Store
        masterChannel: AsyncChannel[int]


var globalTable: ptr UncheckedArray[DualChan]
var globalCounter: Atomic[uint16]

proc close(c: DualChanPtr) = c.first.close(); c.second.close()

proc acceptcidloop(){.async.} =
    await sleepAsync(5000)


proc handleCid(cid: int){.async.} =
    await sleepAsync(5000)
    # try:
    #     handleCancel: await handle_fut
    # finally:
    #     self.handle_cid_futs.remove handle_fut

method init(self: MuxAdapetr, name: string, master: AsyncChannel[int], store: Store, loc: Location, cid: int = 0): MuxAdapetr =
    new result
    result.dataAvailable = newAsyncEvent()
    result.location = loc
    result.store = store
    result.masterChannel = master
    procCall init(Adapter(self), name, hsize = 0)


    if self.getNext != nil:
        doAssert self.getPrev == nil, "Adapters rule broken, the chain is not finished."
        self.side = Side.Left
    else:
        self.side = Side.Right


    case self.location:
        of BeforeGfw:
            case self.side:
                of Side.Left:
                    # left mode, we create and send cid signal
                    let cid = globalCounter.fetchAdd(1).int
                    globalTable[cid].first = newAsyncChannel[StringView]()
                    globalTable[cid].second = newAsyncChannel[StringView]()
                    self.selectedCon = (cid, addr globalTable[cid])
                    asyncSpawn self.masterChannel.send cid

                of Side.Right:
                    # right side, we accept cid signals
                    self.acceptInputFuture = acceptcidloop()

        of AfterGfw:
            case self.side:
                of Side.Left:
                    # left mode, we have been created by a cid
                    doAssert not (isNil(globalTable[cid].first) or isNil(globalTable[cid].second)), "cid was nil in GlobalTable"
                    self.selectedCon = (cid, addr globalTable[cid])

                        #got a cid, handle its read and write and close
                    self.handles.add(handlecid cid)

                of Side.Right:
                    # right side, we send cid signals
                    # its done on write func
                    discard



# proc new*(t: typedesc[MuxAdapetr], loc: Location): MuxAdapetr =
#     trace "new MuxAdapetr"

#     result = MuxAdapetr()
#     result.init(name = "MuxAdapetr")


method write*(self: MuxAdapetr, rp: StringView, chain: Chains = default): Future[void] {.async.} =
    debug "Write", adaptername = self.name, size = rp.len

    case self.location:
        of BeforeGfw:
            case self.side:
                of Side.Left:
                    rp.shiftl MuxHeaderLen
                    rp.write($(self.selectedCon.cid), MuxHeaderLen)
                    await self.selectedCon.first.write()
                of Side.Right:
                    if rp.len < MuxHeaderLen:
                        trace "Write failed, packet was too small",adaptername = self.name
                        return
                    
                    var cid: uint16 = 0
                    copyMem(addr cid, rp.buf(), sizeof(cid))
                    rp.shiftr MuxHeaderLen

                    read mux header from packet.read cid
                    if self.globaltable[cid]:
                        await self.globaltable[cid].second.write()
                    else:
                        send back with no data means closed


        of AfterGfw:
            case self.side:
                of Side.Left: discard
                of Side.Right: discard





    # self.writeLine = rp
    # #wrote to socket
    # await sleepAsync(2)
    # self.wrotestr = $self.writeLine

    # self.writeLine.restart()



method read*(self: MuxAdapetr, chain: Chains = default): Future[StringView] {.async.} =
    info "read", adaptername = self.name

    case self.location:
        of BeforeGfw:
            case self.side:
                of Side.Left: discard

                of Side.Right: discard

        of AfterGfw:
            case self.side:
                of Side.Left: discard
                of Side.Right: discard

    # self.readLine.restart()

    # await sleepAsync(2)
    # self.readLine.write(self.wrotestr)

    # return self.readLine


method signal*(self: MuxAdapetr, dir: SigDirection, sig: Signals, chain: Chains = default) =
    trace "received signal", name = self.name, sig = sig
    procCall signal(Tunnel(self), dir, sig, chain)

    # breakthrough
    if sig == close or sig == stop:
        self.stopped = true
        if self.selectedCon.cid != 0:
            close(self.selectedCon.dcp)
        cancelSoon(self.acceptInputFuture)
        self.handles.apply do(x: Future[void]): cancelSoon x

    if sig == breakthrough: doAssert self.stopped, "break through signal while still running?"




proc staticInit() =
    logScope:
        topic = "Global Memory"
    globalCounter.store(0)
    var total_size = sizeof(typeof(globalTable[][0])) * GlobalTableSize
    globalTable = cast[typeof globalTable](allocShared0(total_size))
    trace "Allocate globalTable", size = total_size
    static: doAssert sizeof(typeof(globalTable[][0])) <= 16, "roye google chromo sefid nakon plz !"
    trace "Initialized"

staticInit()
