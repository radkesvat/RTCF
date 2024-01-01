import tunnel, store
# from adapters/mux import MuxAdapetr
logScope:
    topic = "TransportIdent Tunnel"


#       1    2    3    4    5    6    7
# ------------------------------------
#  flags|
#-------------------------------------
# Trans |
#-------------------------------------
#
#  This tunnel identify the incoming packet trasport , it reads the 8 bit flag
#  it also discardes fake upload packets
#
#
#
#

type
    TransportHeader = uint8
    TransportIdentTunnel* = ref object of Tunnel
        header: TransportHeader
        store: Store

const TransportIdentTunnelHeaderSize = sizeof TransportHeader

from tunnels/tcp import TcpPacketFlag,FakeUploadFlag
from tunnels/udp import UdpPacketFlag


method init(self: TransportIdentTunnel, name: string){.base, raises: [], gcsafe.} =
    procCall init(Tunnel(self), name, hsize = TransportIdentTunnelHeaderSize)
    self.header = 0x0

proc newTransportIdentTunnel*( name: string = "TransportIdentTunnel"): TransportIdentTunnel =
    result =  TransportIdentTunnel()
    result.init(name)
    trace "Initialized", name

method write*(self: TransportIdentTunnel, data: StringView, chain: Chains = default): Future[void] {.raises: [], gcsafe.} =
    assert self.header != 0x0, "cannot write before first read af transport header to identify!"
    setWriteHeader(self, data):
        copyMem(self.getWriteHeader, addr self.header, self.hsize)
        trace "Appended ", header = $self.header, name = self.name

    procCall write(Tunnel(self), self.writeLine)



method read*(self: TransportIdentTunnel, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    while true:
        setReadHeader(self, await procCall read(Tunnel(self), bytes+self.hsize))
        if self.header == 0x0:
            copyMem(addr self.header, self.getReadHeader, self.hsize)
            self.header = self.header and (not FakeUploadFlag)

        trace "extracted ", header = $self.getReadHeader[][0]
        if (self.getReadHeader[][0] and FakeUploadFlag) == FakeUploadFlag:
            trace "discarded received fake packet", bytes = self.readLine.len
        else:
            return self.readLine





proc isTcp*(self: TransportIdentTunnel): bool = (self.header and TcpPacketFlag) == TcpPacketFlag
proc isUcp*(self: TransportIdentTunnel): bool = (self.header and FakeUploadFlag) == FakeUploadFlag
