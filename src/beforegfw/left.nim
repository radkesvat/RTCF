import chronos, chronos/transports/ipnet, chronos/osdefs
import adapters/[connection, mux]
import tunnel, tunnels/[port, tcp]
import  shared
from globals import nil

logScope:
    topic = "Iran LeftSide"


proc startTcpListener(threadID: int) {.async: (raises: []).} =
    {.cast(gcsafe).}:
       
        proc serveStreamClient(server: StreamServer,
                        transp: StreamTransport){.async: (raises: []).}=
            try:


                if not isPeerConnected:
                    error "user connection but no foreign server connected yet!, closing..."
                    transp.close(); return

                let address = transp.remoteAddress()
                trace "Got connection", form = address
                block spawn:
                    var con_adapter = newConnectionAdapter(socket = transp, store = publicStore)
                    var port_tunnel = newPortTunnel(multiport = globals.multi_port, writeport = globals.listen_port)
                    var tcp_tunnel = newTcpTunnel(store = publicStore, fakeupload_ratio = globals.noise_ratio.int)
                    var mux_adapter = newMuxAdapetr(master = masterChannel, store = publicStore, loc = BeforeGfw)
                    con_adapter.chain(port_tunnel).chain(tcp_tunnel).chain(mux_adapter)
                    con_adapter.signal(both, start)

            except CatchableError as e:
                error "handle client connection error", name = e.name, msg = e.msg


        var address:TransportAddress
        try:
            address = initTAddress(globals.listen_addr, globals.listen_port.Port)
        except CatchableError as e:
                fatal "initTAddress failed", name = e.name, msg = e.msg
                quit(1)

        let server: StreamServer =
            try:
                var flags = {ServerFlags.TcpNoDelay, ServerFlags.ReuseAddr, ServerFlags.ReusePort}
                if globals.keep_system_limit:
                    flags.excl ServerFlags.TcpNoDelay
                createStreamServer(address, serveStreamClient, flags = flags, dualstack = Enabled)
            except CatchableError as e:
                fatal "StreamServer creation failed", name = e.name, msg = e.msg
                quit(1)

        try:
            server.start()
            info "Started tcp server", listen = globals.listen_addr, port = globals.listen_port
            await server.join()
        except CatchableError as e:
            fatal "StreamServer start failed", name = e.name, msg = e.msg
            quit(1)

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
    # discard logs()
    dynamicLogScope(thread):
        await startTcpListener(thread)


