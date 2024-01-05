import chronos, chronos/transports/ipnet, chronos/osdefs
import adapters/[ws, mux]
import tunnel
import shared
import websock/[websock, extensions/compression/deflate]

from globals import nil

logScope:
    topic = "Iran RightSide"

var foundpeer = false
var sw: WSSession = nil
var sr: WSSession = nil

var activeCons = 0


proc handle(request: HttpRequest) {.async.} =

    trace "Handling request:", uri = request.uri.path
    var address = request.stream.writer.tsource.remoteAddress()

    if request.uri.path != "/ws" & $globals.sh1:
        request.stream.close()
        warn "rejected websocket connection, password mismatch!"
        return

    try:
        let foctories = case globals.compressor:
            of deflate:
                @[deflateFactory()]
            else:
                @[]

        let server = WSServer.new(factories = foctories)
        let ws = await server.handleRequest(request)
        if ws.readyState != Open:
            error "Failed to open websocket connection"
            return

        # trace "Websocket handshake completed"
        info "Got Websocket connection !"
        {.cast(raises: []), gcsafe.}:
            if sw == nil:
                sw = ws
            else:
                sr = ws
                setIsPeerConnected true
                inc activeCons

                var mux_adapter = newMuxAdapetr(master = masterChannel, store = publicStore, loc = BeforeGfw)
                var ws_adapter = newWebsocketAdapter(socketr = sr, socketw = sw, store = publicStore, onClose =
                    proc() =
                        dec activeCons; if activeCons <= 0: setIsPeerConnected false
                )
                mux_adapter.chain(ws_adapter)
                mux_adapter.signal(both, start)
                sr = nil; sw = nil



    except WebSocketError as e:
        error "Websocket error", name = e.name, msg = e.msg



proc startWebsocketServer(threadID: int) {.async.} =
    {.cast(gcsafe).}:
        var socketFlags = {ServerFlags.TcpNoDelay, ServerFlags.ReuseAddr, ServerFlags.ReusePort}
        if globals.keep_system_limit:
            socketFlags.excl ServerFlags.TcpNoDelay


        var server =
            # HttpServer.create(initTAddress("127.0.0.1:8888"), flags = socketFlags)
            TlsHttpServer.create(
                address = initTAddress(globals.listen_addr, globals.cf_listen_port),
                tlsPrivateKey = TLSPrivateKey.init(globals.pkey),
                tlsCertificate = TLSCertificate.init(globals.cert),
                flags = socketFlags)


        proc accepts() {.async.} =
            while true:
                try:
                    let req = await server.accept()
                    await req.handle()
                except CatchableError as e:
                    error "Https Accept error", name = e.name, msg = e.msg

        asyncSpawn accepts()


        info "Started Ws Server", internalPort = globals.cf_listen_port
        await server.join()

proc logs(){.async.} =
    while true:
        echo "right"
        await sleepAsync(1.seconds)


proc run*(thread: int) {.async.} =
    await sleepAsync(200.milliseconds)
    # if globals.accept_udp:
    #     info "Mode Iran (Tcp + Udp)"
    # else:
    #     info "Mode Iran"
    # asyncSpawn logs()
    dynamicLogScope(thread):
        await startWebsocketServer(thread)


