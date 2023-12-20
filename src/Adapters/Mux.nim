import tunnel, strutils, stew/byteutils, threading/[channels, atomics], store

# This module unfortunately has global shared memory as part of its state

logScope:
    topic = "Mux Adapter"


const
    GlobalTableSize = int(uint16.high) + 1


type
    Chan = AsyncChannel[StringView]

    DualChan {.packed.} = object
        first: Chan
        second: Chan

    DualChanPtr = ptr DualChan

    Location* = enum
        BeforeGfw, AfterGfw

    Side* = enum
        Left, Right

    MuxAdapetr* = ref object of Adapter
        location: Location
        side: Side
        selectedCon: DualChan

        buffered: seq[StringView]
        dataAvailable: AsyncEvent
        acceptIncomeFuture: Future[void]
        handles: seq[Future[void]]
        store: Store


var globalTable: ptr UncheckedArray[DualChan]

var tableCounter: Atomic[uint16]


method init(self: MuxAdapetr, name: string, store: Store,){.base, raises: [], gcsafe.} =

    procCall init(Adapter(self), name, hsize = 0)

# proc new*(t: typedesc[MuxAdapetr], loc: Location): MuxAdapetr =
#     trace "new MuxAdapetr"

#     result = MuxAdapetr()
#     result.init(name = "MuxAdapetr")


# method write*(self: MuxAdapetr, rp: StringView, chain: Chains = default): Future[void] {.async.} =
#     info "Adapter write to socket", adapter = self.name, data = $rp
#     self.writeLine = rp
#     #wrote to socket
#     await sleepAsync(2)
#     self.wrotestr = $self.writeLine

#     self.writeLine.restart()



# method read*(self: MuxAdapetr, chain: Chains = default): Future[StringView] {.async.} =
#     info "Adapter read from socket", adapter = self.name, data = self.wrotestr
#     self.readLine.restart()

#     await sleepAsync(2)
#     self.readLine.write(self.wrotestr)

#     return self.readLine


# method signal*(self: MuxAdapetr, dir: SigDirection, sig: Signals, chain: Chains = default) =
#     info "Adapter received signal", sig = sig
#     self.receivedsig = sig


proc staticInit() =
    tableCounter.store(0)
    var total_size = sizeof(typeof(globalTable[][0])) * GlobalTableSize
    globalTable = cast[typeof globalTable](allocShared(total_size))
    trace "Allocate globalTable", size = total_size
    static: doAssert sizeof(typeof(globalTable[][0])) <= 16, "what the fuck are you doing ?"
    trace "Initialized"

staticInit()
