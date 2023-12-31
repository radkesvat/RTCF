import chronos, chronos/transports/[datagram, ipnet], chronos/osdefs
import adapters/[ws, connection, mux, connector]
import tunnel, tunnels/[port, tcp, udp, transportident]
import store, shared, httputils
import websock/[websock, extensions/compression/deflate]

from globals import nil

logScope:
    topic = "Kharej RightSide"


const parallel_cons = 8

proc connect():Future[WSSession] {.async.} =
    {.cast(gcsafe).}:
        try:
            let deflateFactory = deflateFactory()
            let ws = when true:
                await WebSocket.connect(
                    globals.cdn_domain & ":" & $globals.iran_port,
                    hostname = globals.cdn_domain,
                    path = "/ws" & $globals.sh1,
                    secure = true,
                    factories = @[],
                    flags = {})
                else:
                    await WebSocket.connect(
                        initTAddress(globals.cdn_domain, globals.iran_port),
                        path = "/ws" & $globals.sh1,
                        factories = [deflateFactory])

            return ws
        except [WebSocketError, HttpError]:
            var e = getCurrentException()
            error "Websocket error", name = e.name, msg = e.msg
            quit(1)


proc standAloneChain(){.async.} =
    trace "Initiating connection"
    var ws_r = await connect()
    var ws_w = await connect()
    
    var mux_adapter = newMuxAdapetr(master = masterChannel, store = publicStore, loc = AfterGfw)
    var ws_adapter = newWebsocketAdapter(socketr = ws_r,socketw = ws_w, store = publicStore)
    mux_adapter.chain(ws_adapter)
    mux_adapter.signal(both, start)



proc logs(){.async.}=
    while true:
        echo "right"
        await sleepAsync(1000)


proc run*(thread: int) {.async.} =
    await sleepAsync(200)
    #     info "Mode Kharej"
    # asyncSpawn logs()

    dynamicLogScope(thread):
        for i in 0 ..< parallel_cons:
            await standAloneChain()


