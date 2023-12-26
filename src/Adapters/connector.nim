import tunnel, strutils, store
import sequtils, chronos/transports/stream
import tunnels/transportident 
import tunnels/port 
# This module unfortunately has global shared memory as part of its state

logScope:
    topic = "Connectior Adapter"


#     1    2    3    4    5    6    7 ...
# ---------------------------------------------------
#                 User Requets
# ---------------------------------------------------
#     Connectior contains variable lenght data      |
# ---------------------------------------------------


type
    Protocol = enum
        Tcp,Udp
    ConnectorAdapter* = ref object of Adapter
        socket: StreamTransport
        readLoopFut: Future[void]
        writeLoopFut: Future[void]
        store: Store
        protocol:Protocol
        isMultiPort:bool
        targetIp:IpAddress
        targetPort:Port


const
    bufferSize = 4096


proc getRawSocket*(self: ConnectorAdapter): StreamTransport {.inline.} = self.socket

proc connect(self: ConnectorAdapter) {.async.}=
    assert self.socket == nil
    var (tident,_) = self.findByType(TransportIdentTunnel,right)
    doAssert tident != nil, "connector adapter could not locate TransportIdentTunnel! it is required"
    self.protocol =  if tident.isTcp : Tcp else: Udp

    if self.isMultiPort:
        var (port_tunnel,_) = self.findByType(PortTunnel,right)
        doAssert port_tunnel != nil, "connector adapter could not locate PortTunnel! it is required"
        self.targetPort = port_tunnel.getReadPort()
    if self.protocol == Tcp:
        var target = initTAddress(self.targetIp, self.targetPort)
        for i in 0 .. 4:
            try:
                var flags = {SocketFlags.TcpNoDelay, SocketFlags.ReuseAddr}
                self.socket = await connect(target, flags = flags)

            except CatchableError as e:
                error "could not connect TCP to the core! ", name = e.name, msg = e.msg
                if i != 4: notice "retrying ...", tries = i
                else: error "so... giving up", tries = i

proc writeloop(self: ConnectorAdapter){.async.} =
    #read data from socket, write to chain
    var socket = self.socket
    try:
        while not socket.closed and not self.stopped:
            var sv = self.store.pop()
            sv.reserve(bufferSize)
            var actual = await socket.readOnce(sv.buf(), bufferSize)

            if actual == 0:
                trace "close for 0 bytes read from socket"; break
            else:
                trace "read bytes from socket", count= actual

            sv.setLen(actual)
            await procCall write(Tunnel(self), sv)

    except CatchableError as e:
        if e.meansCancel():
            trace "writeloop got canceled", name = e.name, msg = e.msg
        else:
            error "writeloop got Exception", name = e.name, msg = e.msg
            raise e
    if not self.stopped: signal(self, both, close)


# called when we are on the right side
proc readloop(self: ConnectorAdapter){.async.} =
    #read data from chain, write to socket
    var socket = self.socket
    try:
        while not socket.closed and not self.stopped:
            var sv = await procCall read(Tunnel(self), 1)
            trace "write bytes to socket", count = sv.len
            if socket == nil:
                await self.connect()
                self.writeLoopFut = self.writeloop()
                asyncSpawn self.writeLoopFut

            if sv.len != await socket.write(sv.buf, sv.len):
                raise newAsyncStreamIncompleteError()

    except CatchableError as e:
        if e.meansCancel():
            trace "readloop got canceled", name = e.name, msg = e.msg
        else:
            error "readloop got Exception", name = e.name, msg = e.msg
            raise e
        
    if not self.stopped: signal(self, both, close)




method init(self: ConnectorAdapter, name: string, isMultiPort:bool,targetIp:IpAddress,targetPort:Port, store: Store){.raises: [].} =
    procCall init(Adapter(self), name, hsize = 0)
    self.store = store
    self.isMultiPort = isMultiPort
    self.targetIp = targetIp
    self.targetPort = targetPort



proc newConnectorAdapter*(name: string = "ConnectorAdapter",isMultiPort:bool,targetIp:IpAddress,targetPort:Port, store: Store): ConnectorAdapter {.raises: [].} =
    result = new ConnectorAdapter
    result.init(name, isMultiPort,targetIp,targetPort, store)
    trace "Initialized", name


method write*(self: ConnectorAdapter, rp: StringView, chain: Chains = default): Future[void] {.async.} =
    doAssert false, "you cannot call write of ConnectorAdapter!"

method read*(self: ConnectorAdapter, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    doAssert false, "you cannot call read of ConnectorAdapter!"


method start(self: ConnectorAdapter){.raises: [].} =
    {.cast(raises: []).}:
        procCall start(Adapter(self))
        trace "starting"

        self.readLoopFut = self.readloop()
        asyncSpawn self.readLoopFut
        

            
proc stop*(self: ConnectorAdapter) =
    if not self.stopped:
        trace "stopping"
        self.stopped = true
        cancelSoon self.readLoopFut
        cancelSoon self.writeLoopFut
        self.socket.close()

method signal*(self: ConnectorAdapter, dir: SigDirection, sig: Signals, chain: Chains = default){.raises: [].} =
    if sig == close or sig == stop: self.stop()

    if sig == breakthrough: doAssert self.stopped, "break through signal while still running?"

    procCall signal(Tunnel(self), dir, sig, chain)

    if sig == start: self.start()


