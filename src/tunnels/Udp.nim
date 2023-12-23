import tunnel, stew/byteutils, threading/[channels, atomics], store
# from adapters/mux import MuxAdapetr
logScope:
    topic = "Udp Tunnel"


#       1    2    3    4    5    6    7
# ------------------------------------
#  flags|
#-------------------------------------
#   Udp|
#-------------------------------------
#
#   This tunnel show the protocol used for creation of the packet which is Udp
#   also this tunnel can do fake upload, very similar to Udp but with different
#   header,
#
#
#
#

type
    UdpHeader = uint8
    UdpTunnel = ref object of Tunnel
        fakeupload_ratio: int
        fakeupload_bytes_left: uint64
        header:UdpHeader
        store: Store

const UdpTunnelHeaderSize = sizeof UdpHeader
const UdpPacketFlag*: UdpHeader = 0b00000010
from tunnels/tcp import FakeUploadFlag

method init(self: UdpTunnel, name: string, store: Store, fakeupload_ratio: int){.base, raises: [], gcsafe.} =
    procCall init(Tunnel(self), name, hsize = UdpTunnelHeaderSize)
    self.fakeupload_ratio = fakeupload_ratio
    self.store = store
    self.header = UdpPacketFlag

proc new*(t: typedesc[UdpTunnel], name: string = "UdpTunnel", store: Store, fakeupload_ratio: int = 0): UdpTunnel =
    result = new UdpTunnel
    result.init(name, store, fakeupload_ratio)
    trace "Initialized", name

method write*(self: UdpTunnel, data: StringView, chain: Chains = default): Future[void] {.async.} =
    setWriteHeader(self, data):
        copyMem(self.getWriteHeader, addr self.header, self.hsize)
        trace "Appended ", header = $self.header, to = ($self.writeLine), name = self.name

    await procCall write(Tunnel(self), self.writeLine)
    if 0 < self.fakeupload_ratio:
        var fakepacket = self.store.pop()
        fakepacket.setLen(data.len)
        copyMem(fakepacket.buf, self.store.getRandomBuf(1000), data.len)
        fakepacket.write(UdpPacketFlag and FakeUploadFlag)
        await procCall write(Tunnel(self), self.writeLine)


method read*(self: UdpTunnel, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    while true:
        setReadHeader(self, await procCall read(Tunnel(self), bytes+self.hsize))
        # copyMem(addr self.readPort, self.getReadHeader, self.hsize)
        assert (self.getReadHeader[][0] and UdpPacketFlag) == UdpPacketFlag, "received packet protocol mismatch!"
        trace "extracted ", header = $self.getReadHeader[][0], result = $self.readLine
        if (self.getReadHeader[][0] and FakeUploadFlag) == FakeUploadFlag:
            trace "discarded received fake packet", bytes = self.readLine.len
        else:
            return self.readLine






