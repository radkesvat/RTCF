import tunnel,  store
import chronos/transports/stream
import tunnels/[transportident,port]


logScope:
    topic = "Connector Adapter"


#     1    2    3    4    5    6    7 ...
# ---------------------------------------------------
#                 User Requets
# ---------------------------------------------------
#     Connector contains variable lenght data      |
# ---------------------------------------------------


type
    Protocol = enum
        Tcp, Udp
    ConnectorAdapter* = ref object of Adapter
        socket: StreamTransport
        readLoopFut: Future[void]
        writeLoopFut: Future[void]
        store: Store
        protocol: Protocol
        isMultiPort: bool
        targetIp: IpAddress
        targetPort: Port
        connecting: bool
        connectingFut: AsyncEvent
        test: bool


const
    bufferSize = 4093
    writeTimeOut = 5
    readTimeOut = 200

proc getRawSocket*(self: ConnectorAdapter): StreamTransport {.inline.} = self.socket
proc writeloop(self: ConnectorAdapter){.async.} =
    #read data from socket, write to chain
    var sv: StringView = nil
    while not self.stopped:
        try:
            sv = self.store.pop()
            sv.reserve(bufferSize)
            var actual = await self.socket.readOnce(sv.buf(), bufferSize)
            if actual == 0:
                trace "Writeloop read 0 !";
                self.store.reuse move sv
                if not self.stopped: signal(self, both, close)
                break
            else:
                trace "Writeloop read", bytes = actual
            sv.setLen(actual)

        except [CancelledError, TransportError, AsyncError,AsyncChannelError]:
            var e = getCurrentException()
            trace "Writeloop Cancel [Read]", msg = e.name
            self.store.reuse sv
            if not self.stopped: signal(self, both, close)
            return
        except CatchableError as e:
            error "Writeloop Unexpected Error [Read]", name = e.name, msg = e.msg
            quit(1)


        try:
            trace "Writeloop write", bytes = sv.len
            if self.stopped: return

            await procCall write(Tunnel(self), move sv)

        except [CancelledError, FlowError, AsyncError,AsyncChannelError]:
            var e = getCurrentException()
            trace "Writeloop Cancel [Write]", msg = e.name
            if sv != nil: self.store.reuse sv
            if not self.stopped: signal(self, both, close)
            return
        except CatchableError as e:
            error "Writeloop Unexpected Error [Write]", name = e.name, msg = e.msg
            quit(1)


proc connect(self: ConnectorAdapter): Future[bool] {.async.} =
    assert self.socket == nil
    assert not self.test
    self.test = true
    var (tident, _) = self.findByType(TransportIdentTunnel, right)
    doAssert tident != nil, "connector adapter could not locate TransportIdentTunnel! it is required"
    self.protocol = if tident.isTcp: Tcp else: Udp

    if self.isMultiPort:
        var (port_tunnel, _) = self.findByType(PortTunnel, right)
        doAssert port_tunnel != nil, "connector adapter could not locate PortTunnel! it is required"
        self.targetPort = port_tunnel.getReadPort()
    self.connecting = true
    if self.protocol == Tcp:
        var target = initTAddress(self.targetIp, self.targetPort)
        for i in 0 .. 4:
            try:
                var flags = {SocketFlags.TcpNoDelay, SocketFlags.ReuseAddr}
                self.socket = await connect(target, flags = flags)
                trace "connected to the target core"
                self.connectingFut.fire()
                self.writeLoopFut = self.writeloop()
                asyncSpawn self.writeLoopFut
                return true
            except CatchableError as e:
                error "could not connect TCP to the core! ", name = e.name, msg = e.msg
                if i != 4: notice "retrying ...", tries = i
                else: error "give up connecting to core", tries = i; return false
            finally:
                self.connecting = false
    else:
        quit(1)



proc readloop(self: ConnectorAdapter){.async.} =
    #read data from chain, write to socket
    var sv: StringView = nil
    while not self.stopped:
        try:
            sv = await procCall read(Tunnel(self), 1)
            trace "Readloop Read", bytes = sv.len
        except [CancelledError, FlowError,AsyncChannelError]:
            var e = getCurrentException()
            warn "Readloop Cancel [Read]", msg = e.name
            if not self.stopped: signal(self, both, close)
            return
        except CatchableError as e:
            error "Readloop Unexpected Error, [Read]", name = e.name, msg = e.msg
            quit(1)


        if not self.stopped and self.socket == nil:
            if self.connecting:
                await self.connectingFut.wait()
            elif await connect(self):discard
            else:
                self.store.reuse move sv
                if not self.stopped: signal(self, both, close)
                return

        try:
            trace "Readloop write to socket", count = sv.len
            if self.stopped: return

            if sv.len != await self.socket.write(sv.buf, sv.len):
                raise newAsyncStreamIncompleteError()


        except [CancelledError, FlowError, TransportError,AsyncChannelError, AsyncStreamError]:
            var e = getCurrentException()
            warn "Readloop Cancel [Write]", msg = e.name
            if not self.stopped: signal(self, both, close)
            return
        except CatchableError as e:
            error "Readloop Unexpected Error, [Write]", name = e.name, msg = e.msg
            quit(1)
        finally:
            self.store.reuse move sv




proc init(self: ConnectorAdapter, name: string, isMultiPort: bool, targetIp: IpAddress, targetPort: Port, store: Store){.raises: [].} =
    procCall init(Adapter(self), name, hsize = 0)
    self.store = store
    self.isMultiPort = isMultiPort
    self.targetIp = targetIp
    self.targetPort = targetPort



proc newConnectorAdapter*(name: string = "ConnectorAdapter", isMultiPort: bool, targetIp: IpAddress, targetPort: Port,
        store: Store): ConnectorAdapter {.raises: [].} =
    result = new ConnectorAdapter
    result.init(name, isMultiPort, targetIp, targetPort, store)
    trace "Initialized", name


method write*(self: ConnectorAdapter, rp: StringView, chain: Chains = default): Future[void] {.async.} =
    doAssert false, "you cannot call write of ConnectorAdapter!"

method read*(self: ConnectorAdapter, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    doAssert false, "you cannot call read of ConnectorAdapter!"


method start(self: ConnectorAdapter){.raises: [].} =
    {.cast(raises: []).}:
        procCall start(Adapter(self))
        trace "starting"
        self.connectingFut = newAsyncEvent()
        self.readLoopFut = self.readloop()
        asyncSpawn self.readLoopFut

proc stop*(self: ConnectorAdapter) =
    proc breakCycle(){.async.} =
        await sleepAsync(2.seconds)
        self.signal(both, breakthrough)

    if not self.stopped:
        trace "stopping"
        self.stopped = true
        if not isNil(self.socket): self.socket.close()
        if not isNil(self.readLoopFut): cancelSoon self.readLoopFut
        if not isNil(self.writeLoopFut): cancelSoon self.writeLoopFut
        asyncSpawn breakCycle()

method signal*(self: ConnectorAdapter, dir: SigDirection, sig: Signals, chain: Chains = default){.raises: [].} =

    if sig == breakthrough: doAssert self.stopped, "break through signal while still running?"
    if sig == close or sig == stop: self.stop()

    procCall signal(Tunnel(self), dir, sig, chain)

    if sig == start: self.start()


