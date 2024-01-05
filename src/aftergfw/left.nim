import chronos, chronos/transports/ipnet
import adapters/[mux, connector], tunnel, tunnels/[port, transportident]
import shared
from globals import nil

logScope:
    topic = "Kharej LeftSide"


proc startCoreConnector(threadID: int) {.async.} =
    {.cast(gcsafe).}:
        while true:
            let cid = await masterChannel.recv()
            trace "Got connection request"
            var targetip = parseIpAddress(globals.next_route_addr)
            block spawn:
                var con_adapter = newConnectorAdapter(store = publicStore, ismultiport = globals.multi_port, targetIp = targetip,
                targetPort = Port(globals.next_route_port))
                var port_tunnel = newPortTunnel(multiport = globals.multi_port, writeport = 0.Port)
                var tident_tunnel = newTransportIdentTunnel()
                var mux_adapter = newMuxAdapetr(cid = cid, master = masterChannel, store = publicStore, loc = AfterGfw)
                con_adapter.chain(port_tunnel).chain(tident_tunnel).chain(mux_adapter)
                con_adapter.signal(both, start)


proc logs(){.async.} =
    while true:
        echo "left"
        await sleepAsync(1.seconds)

        
proc run*(thread: int) {.async.} =
    await sleepAsync(200.milliseconds)
    # if globals.accept_udp:
    #     info "Mode Iran (Tcp + Udp)"
    # else:
    #     info "Mode Iran"
    # asyncSpawn logs()

    dynamicLogScope(thread):
        await startCoreConnector(thread)


