import tunnel, stew/byteutils, threading/[channels, atomics]
# from adapters/mux import MuxAdapetr
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
#
#



type
    Port = uint16
    PortTunnel = ref object of Tunnel
        writePort: Port
        readPort: Port
        multiport:bool

const PortTunnelHeaderSize = sizeof(Port)

method init(self: PortTunnel, name: string,multiport:bool ,writeport:Port){.base, raises: [], gcsafe.} =
    procCall init(Tunnel(self), name, hsize = PortTunnelHeaderSize)
    self.writeport = writeport
    self.multiport = multiport

proc new*(t: typedesc[PortTunnel], name: string = "PortTunnel",multiport:bool, writeport:int = 0): PortTunnel =
    result = new PortTunnel
    result.init(name ,multiport,writeport.Port)
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
    if self.writeport == 0: self.writeport = self.readPort # just for hint
    return self.readLine


proc start(self: PortTunnel) = discard
    #Todo:
    # if multi port and a connecton adapter found on the left
    # get the connection port and set as write port
    # else

    # var (target, dir) = self.findByType(MuxAdapetr, both, Chains.default)
    # self.flow = dir
    # doAssert not isNil(target), "PortTunnel could not find Mux adapter in current chain."
    #Todo: find connection adapter, get socket from it and set the write port to it

method signal*(self: PortTunnel, dir: SigDirection, sig: Signals, chain: Chains = default) =
    if signal == start: self.start()
    procCall signal(Tunnel(self), dir, sig, chain)




