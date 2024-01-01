import chronos, chronos/transports/ipnet, chronos/osdefs
import adapters/[ws, mux], tunnel
import store, shared, httputils
import websock/[websock, extensions/compression/deflate]

from globals import nil

logScope:
    topic = "Kharej RightSide"


const parallel_cons = 2

proc connect():Future[WSSession] {.async.} =
    {.cast(gcsafe).}:
        try:
            let foctories = case globals.compressor:
            of deflate:
                @[deflateFactory()]
            else:
                @[]
            let ws = when true:
                await WebSocket.connect(
                    globals.cdn_domain & ":" & $globals.iran_port,
                    hostname = globals.cdn_domain,
                    path = "/ws" & $globals.sh1,
                    secure = true,
                    factories = foctories,
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
    info "Connected to the target!"


proc logs(){.async.}=
    while true:
        echo "right"
        await sleepAsync(1.seconds)


proc run*(thread: int) {.async.} =
    await sleepAsync(200.milliseconds)
    #     info "Mode Kharej"
    # asyncSpawn logs()

    dynamicLogScope(thread):
        for i in 0 ..< parallel_cons:
            await standAloneChain()


