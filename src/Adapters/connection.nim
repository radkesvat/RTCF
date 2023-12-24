import tunnel, strutils, store
import sequtils, chronos/transports/stream
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
    ConnectionAdapter* = ref object of Adapter
        socket: StreamTransport
        readLoopFut: Future[void]
        writeLoopFut: Future[void]
        store: Store

const
    bufferSize = 4096


proc getRawSocket*(self: ConnectionAdapter): StreamTransport {.inline.} = self.socket

# called when we are on the right side
proc readloop(self: ConnectionAdapter){.async.} =
    #read data from chain, write to socket
    var socket = self.socket
    try:
        while not socket.closed and not self.stopped:
            var sv = await procCall read(Tunnel(self), 1)
            if sv.len != await socket.write(sv.buf, sv.len):
                raise newAsyncStreamIncompleteError()
    except CatchableError as e:
        when e is CancelErrors:
            trace "readloop got canceled", name = e.name, msg = e.msg
        else: 
            error "readloop got Exception", name = e.name, msg = e.msg
            raise e
    if not self.stopped: signal(self, both, close)
    

  

proc writeloop(self: ConnectionAdapter){.async.} =
    #read data from socket, write to chain
    var socket = self.socket
    try:
        while not socket.closed and not self.stopped:
            var sv = self.store.pop()
            sv.reserve(bufferSize)
            var actual = await socket.readOnce(sv.buf(), bufferSize)
            if actual == 0:
                trace "close for 0 bytes read from socket"; break

            sv.setLen(actual)
            await procCall write(Tunnel(self), sv)
            
    except CatchableError as e:
        when e is CancelErrors:
            trace "writeloop got canceled", name = e.name, msg = e.msg
        else: 
            error "writeloop got Exception", name = e.name, msg = e.msg
            raise e
    if not self.stopped: signal(self, both, close)
    

method init(self: ConnectionAdapter, name: string, socket: StreamTransport, store: Store): ConnectionAdapter =
    self.socket = socket
    self.store = store
    procCall init(Adapter(self), name, hsize = 0)



proc new*(t: typedesc[ConnectionAdapter], name: string = "ConnectionAdapter", socket: StreamTransport, store: Store): ConnectionAdapter =
    result = new ConnectionAdapter
    result.init(name, socket, store)
    trace "Initialized", name


method write*(self: ConnectionAdapter, rp: StringView, chain: Chains = default): Future[void] {.async.} =
    doAssert false, "you cannot call write of ConnectionAdapter!"

method read*(self: ConnectionAdapter, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    doAssert false, "you cannot call read of ConnectionAdapter!"



proc start(self: ConnectionAdapter) =
    {.cast(raises: []).}:
        self.readLoopFut = self.readloop()
        self.writeLoopFut = self.writeloop()
        asyncSpawn self.readLoopFut
        asyncSpawn self.writeLoopFut

proc stop*(self: ConnectionAdapter)=
    if not self.stopped :
        trace "stopping"
        self.stopped = true
        cancelSoon self.readLoopFut
        cancelSoon self.writeLoopFut     
        self.socket.close()

method signal*(self: ConnectionAdapter, dir: SigDirection, sig: Signals, chain: Chains = default) =
    if sig == close or sig == stop: self.stop()
        
    if sig == start: self.start()
    
    if sig == breakthrough: doAssert self.stopped, "break through signal while still running?"

    procCall signal(Tunnel(self), dir, sig, chain)


