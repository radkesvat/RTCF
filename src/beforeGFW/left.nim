import chronos, chronos/transports/[datagram, ipnet], chronos/osdefs
import adapters/[ws, connection, mux, connector]
import tunnel,tunnels/[port, tcp, udp, transportident]
import store,shared
from globals import nil

logScope:
    topic = "Iran LeftSide"

var threadstore {.threadvar.}: Store

proc startTcpListener(threadID: int) {.async.} =
    {.cast(gcsafe).}:
        proc serveStreamClient(server: StreamServer,
                        transp: StreamTransport) {.async.} =
            try:
                let address = transp.remoteAddress()
                trace "Got connection", form = address
                block spawn:
                    var con_adapter = newConnectionAdapter(socket = transp, store = threadstore)
                    var mux_adapter = newMuxAdapetr(master = masterChannel,store = threadstore,loc = BeforeGfw)
                    con_adapter.chain(mux_adapter)
                    con_adapter.signal(both,start)

            except CatchableError as e:
                error "handle client connection error", name = e.name, msg = e.msg


        var address = initTAddress(globals.listen_addr, globals.listen_port.Port)
        let server: StreamServer =
            try:
                var flags = {ServerFlags.TcpNoDelay, ServerFlags.ReuseAddr, ServerFlags.ReusePort}
                if globals.keep_system_limit:
                    flags.excl ServerFlags.TcpNoDelay
                createStreamServer(address, serveStreamClient, flags = flags)
            except CatchableError as e:
                fatal "StreamServer creation failed", name = e.name, msg = e.msg
                quit(1)

        server.start()
        info "Started tcp server", listen = globals.listen_addr, port = globals.listen_port
        await server.join()



proc run*(thread: int) {.async.} =
    await sleepAsync(200)
    threadstore = newStore()
    # if globals.accept_udp:
    #     info "Mode Iran (Tcp + Udp)"
    # else:
    #     info "Mode Iran"
    dynamicLogScope(thread):
        await startTcpListener(thread)


