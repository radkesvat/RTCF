import chronos, chronos/transports/[datagram, ipnet], chronos/osdefs
import adapters/[ws, connection, mux, connector]
import tunnel, tunnels/[port, tcp, udp, transportident]
import store, shared, httputils
import websock/[websock, extensions/compression/deflate]

from globals import nil

logScope:
    topic = "Kharej RightSide"



proc connect() {.async.} =
    {.cast(gcsafe).}:
        try:
            let deflateFactory = deflateFactory()
            let ws = when true:
                await WebSocket.connect(
                    globals.cdn_domain & ":" & $globals.iran_port,
                    hostname = globals.cdn_domain,
                    path = "/ws" & $globals.sh1,
                    secure = true,
                    factories = @[deflateFactory],
                    flags = {})
                else:
                    await WebSocket.connect(
                        initTAddress(globals.cdn_domain, globals.iran_port),
                        path = "/ws" & $globals.sh1,
                        factories = [deflateFactory])

            var mux_adapter = newMuxAdapetr(master = masterChannel, store = publicStore, loc = AfterGfw)
            var ws_adapter = newWebsocketAdapter(socket = ws, store = publicStore)
            mux_adapter.chain(ws_adapter)
            mux_adapter.signal(both, start)
            await ws.stream.reader.join()

        except [WebSocketError, HttpError]:
            var e = getCurrentException()
            error "Websocket error", name = e.name, msg = e.msg
            quit(1)



proc startWebsocketConnector(threadID: int) {.async.} =
    trace "Initiating connection"
    await connect()

proc logs(){.async.}=
    while true:
        echo publicStore.available.len()
        await sleepAsync(500)

proc run*(thread: int) {.async.} =
    await sleepAsync(200)
    #     info "Mode Kharej"
    # asyncCheck logs()

    dynamicLogScope(thread):
        await startWebsocketConnector(thread)


