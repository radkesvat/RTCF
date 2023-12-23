import tunnel, strutils, store
import sequtils, chronos/stream
# This module unfortunately has global shared memory as part of its state

logScope:
    topic = "Connection Adapter"


#     1    2    3    4    5    6    7 ...
# ---------------------------------------------------
#                 User Requets
# ---------------------------------------------------
#     Connection contains variable lenght data      |
# ---------------------------------------------------


type

    RunMode = enum
        server, connenctor

    ConnectionAdapetr* = ref object of Adapter
        mode: RunMode
        socket: StreamTransport
        readLoopFut: Future[void]
        writeLoopFut: Future[void]
        store: Store

const
    bufferSize = 4096



# called when we are on the right side
proc readloop(self: ConnectionAdapetr){.async.} =
    #read data from chain, write to socket
    var socket = self.socket
    try:
        while not socket:
            while not socket.closed:
                var sv = await procCall read(Tunnel(self), 1)
                await socket.write(sv.buf,sv.len)
    except CatchableError as e:
        trace "Read Loop finished with ", exception = e
    self.signal(stop)

proc writeloop(self: ConnectionAdapetr){.async.} =
    #read data from socket, write to chain
    var socket = self.socket
    try:
        while not socket:
            while not socket.closed:
                var sv = store.pop()
                sv.reserve(bufferSize)
                await socket.readOnce(sv.buf(), bufferSize)
                await procCall write(Tunnel(self), sv)
    except CatchableError as e:
        trace "Write Loop finished with ", exception = e
    self.signal(stop)


method init(self: ConnectionAdapetr, name: string, socket: StreamTransport, store: Store, ): ConnectionAdapetr =
    self.socket = socket
    self.store = store
    procCall init(Adapter(self), name, hsize = 0)
    self.readLoopFut = self.readloop()


    case self.location:
        of BeforeGfw:



            case self.side:
                of Side.Left:
                    # left mode, we create and send our cid signal
                    let cid = globalCounter.fetchAdd(1)
                    globalTable[cid].first = newAsyncChannel[StringView]()
                    globalTable[cid].second = newAsyncChannel[StringView]()
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
                    # right mode, we have been created by left Connection
                    # we find our channels,write and read to it
                    doAssert(self.selectedCon.cid != 0)
                    doAssert(globalTableHas self.selectedCon.cid)
                    self.selectedCon.dcp = addr globalTable[self.selectedCon.cid]




proc new*(t: typedesc[ConnectionAdapetr], name: string = "ConnectionAdapetr", socket: StreamTransport, store: Store, ): ConnectionAdapetr =
    result = new ConnectionAdapetr
    result.init(name, socket, store)
    trace "Initialized new ConnectionAdapetr", name


method write*(self: ConnectionAdapetr, rp: StringView, chain: Chains = default): Future[void] {.async.} =
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

method read*(self: ConnectionAdapetr, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
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
                    assert size > 0
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
                    assert size > 0
                    return sv


proc start(self: ConnectionAdapetr) =
    {.cast(raises: []).}:
        self.readLoopFut = self.readloop()

method signal*(self: ConnectionAdapetr, dir: SigDirection, sig: Signals, chain: Chains = default) =
    if sig == close or sig == stop: self.stopped = true
    if sig == start: self.start()
    procCall signal(Tunnel(self), dir, sig, chain)

    if sig == close or sig == stop:
        self.stopped = true
        if self.selectedCon.cid != 0:
            close(self.selectedCon.dcp)
        if not isNil(self.acceptConnectionFut): cancelSoon(self.acceptConnectionFut)
        if not isNil(self.readloopFut): cancelSoon(self.readloopFut)
        self.handles.apply do(x: Future[void]): cancelSoon x

    if sig == breakthrough: doAssert self.stopped, "break through signal while still running?"


