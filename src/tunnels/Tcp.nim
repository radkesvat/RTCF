import tunnel,  store


logScope:
    topic = "Tcp Tunnel"


#       1    2    3    4    5    6    7
# ------------------------------------
#  flags|
#-------------------------------------
#   Tcp|
#-------------------------------------
#
#   This tunnel show the protocol used for creation of the packet which is tcp
#   also this tunnel can do fake upload
#
#
#
#



type
    TcpHeader = uint8
    TcpTunnel* = ref object of Tunnel
        fakeupload_ratio: int
        fakeupload_bytes_left: uint64
        header: TcpHeader
        store: Store

const TcpTunnelHeaderSize = sizeof TcpHeader
const TcpPacketFlag*: TcpHeader = 0b00000001
const FakeUploadFlag*: TcpHeader = 0b10000000

method init(self: TcpTunnel, name: string, store: Store, fakeupload_ratio: int){.base, raises: [], gcsafe.} =
    procCall init(Tunnel(self), name, hsize = TcpTunnelHeaderSize)
    self.fakeupload_ratio = fakeupload_ratio
    self.store = store
    self.header = TcpPacketFlag

proc new*(t: typedesc[TcpTunnel], name: string = "TcpTunnel", store: Store, fakeupload_ratio: int = 0): TcpTunnel =
    result = new TcpTunnel
    result.init(name, store, fakeupload_ratio)
    trace "Initialized", name

method write*(self: TcpTunnel, data: StringView, chain: Chains = default): Future[void] {.async.} =
    setWriteHeader(self, data):
        copyMem(self.getWriteHeader, addr self.header, self.hsize)
        trace "Appended ", header = $self.header, to = ($self.writeLine), name = self.name

    await procCall write(Tunnel(self), self.writeLine)
    if 0 < self.fakeupload_ratio:
        var fakepacket = self.store.pop()
        fakepacket.setLen(data.len)
        copyMem(fakepacket.buf, self.store.getRandomBuf(1000), data.len)
        fakepacket.write(TcpPacketFlag and FakeUploadFlag)
        try:
            await procCall write(Tunnel(self),fakepacket)
        finally:
            self.store.reuse fakepacket


method read*(self: TcpTunnel, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    while true:
        setReadHeader(self, await procCall read(Tunnel(self), bytes+self.hsize))
        # copyMem(addr self.readPort, self.getReadHeader, self.hsize)
        assert (self.getReadHeader[][0] and TcpPacketFlag) == TcpPacketFlag, "received packet protocol mismatch!"
        trace "extracted ", header = $self.getReadHeader[][0], result = $self.readLine
        if (self.getReadHeader[][0] and FakeUploadFlag) == FakeUploadFlag:
            trace "discarded received fake packet", bytes = self.readLine.len
            self.store.reuse self.readLine
        else:
            return self.readLine





