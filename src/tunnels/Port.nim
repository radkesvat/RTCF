import tunnel
import std/[endians]

from adapters/connection import ConnectionAdapter, getRawSocket



logScope:
    topic = "Port Tunnel"


#     1    2    3    4    5    6    7
# ----------------------------------
#   port    |
# ----------------------------------
#   Port    |
# ----------------------------------
#
#   This tunnel adds port header, finds the right value for the port
#   and when Reading from it , it extcarcts port header and saves it
#   and provide interface for other tunnel/adapters to get that port
#   
#   This tunnel requires ConnectionAdapter 
#
    


const SO_ORIGINAL_DST* = 80
const IP6T_SO_ORIGINAL_DST* = 80
const SOL_IP* = 0
const SOL_IPV6* = 41

type
    PortTunnel* = ref object of Tunnel
        writePort: Port
        readPort: Port
        multiport: bool
        flag_readmode: bool

const PortTunnelHeaderSize = sizeof(Port)

method init(self: PortTunnel, name: string, multiport: bool, writeport: Port){.base, raises: [], gcsafe.} =
    procCall init(Tunnel(self), name, hsize = PortTunnelHeaderSize)
    self.writeport = writeport
    self.multiport = multiport

proc newPortTunnel*( name: string = "PortTunnel", multiport: bool, writeport: Port = 0.Port): PortTunnel =
    result = new PortTunnel
    result.init(name, multiport, writeport)
    trace "Initialized", name

method write*(self: PortTunnel, data: StringView, chain: Chains = default): Future[void] {.raises: [], gcsafe.} =
    setWriteHeader(self, data):
        copyMem(self.getWriteHeader, addr self.writePort, self.hsize)
        trace "Appended ", header = $self.writePort, to = ($self.writeLine), name = self.name

    procCall write(Tunnel(self), self.writeLine)

method read*(self: PortTunnel, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    setReadHeader(self, await procCall read(Tunnel(self), bytes+self.hsize))
    copyMem(addr self.readPort, self.getReadHeader, self.hsize)
    trace "extracted ", header = $self.readPort, result = $self.readLine

    if self.flag_readmode and self.writeport == 0.Port: self.writeport = self.readPort
    return self.readLine


proc start(self: PortTunnel) =
    {.cast(raises: []).}:
        var (target, dir) = self.findByType(ConnectionAdapter, both, Chains.default)
        doAssert target != nil, "Port Tunnel could not find connection adapter on default chain!"
        case dir:
        of left:
            #left means we should get the port from it for writing (only when multi port)
            if self.multiport:
                assert self.writePort == 0.Port
                var sock = target.getRawSocket()
                var objbuf = newString(len = 28)
                var size = int(if isV4Mapped(sock.remoteAddress): 16 else: 28)
                let sol = int(if isV4Mapped(sock.remoteAddress): SOL_IP else: SOL_IPV6)
                if not getSockOpt(sock.fd, sol, int(SO_ORIGINAL_DST),cast[var pointer](addr objbuf[0]), size):
                    trace "multiport failure getting origin port. !"
                    raise newException(AssertionDefect, "multiport failure getting origin port. !")

                bigEndian16(addr self.writePort, addr objbuf[2])
                trace "Multiport ",port = self.writePort
        of right:
            # hmm, the port is received when reading data
            self.flag_readmode = true
        else: discard

method signal*(self: PortTunnel, dir: SigDirection, sig: Signals, chain: Chains = default) =
    procCall signal(Tunnel(self), dir, sig, chain)
    if signal == start: self.start()



proc getReadPort*(self: PortTunnel):Port = self.readPort

