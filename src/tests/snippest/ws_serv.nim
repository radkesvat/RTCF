## nim-websock
## Copyright (c) 2021 Status Research & Development GmbH
## Licensed under either of
##  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
##  * MIT license ([LICENSE-MIT](LICENSE-MIT))
## at your option.
## This file may not be copied, modified, or distributed except according to
## those terms.

import std/uri
import pkg/[chronos,
             chronicles,
             httputils]

import websock/[websock, extensions/compression/deflate]
import keys

proc handle(request: HttpRequest) {.async.} =
  trace "Handling request:", uri = request.uri.path
  echo "handle"
  try:
    let deflateFactory = deflateFactory()
    let server = WSServer.new(factories = [deflateFactory])
    let ws = await server.handleRequest(request)
    if ws.readyState != Open:
      error "Failed to open websocket connection"
      return

    trace "Websocket handshake completed"
    while ws.readyState != ReadyState.Closed:
      let recvData = await ws.recvMsg()
      trace "Client Response: ", size = recvData.len, binary = ws.binary

      if ws.readyState == ReadyState.Closed:
        # if session already terminated by peer,
        # no need to send response
        break

      await ws.send(recvData,
        if ws.binary: Opcode.Binary else: Opcode.Text)

  except WebSocketError as exc:
    error "WebSocket error:", exception = exc.msg

when isMainModule:
  # we want to run parallel tests in CI
  # so we are using different port
  proc main() {.async.} =
    let
      socketFlags = {ServerFlags.TcpNoDelay, ServerFlags.ReuseAddr}
      server = when defined tls:
        echo "tls"

        TlsHttpServer.create(
          address = initTAddress("127.0.0.1:8889"),
          tlsPrivateKey = TLSPrivateKey.init(SecureKey),
          tlsCertificate = TLSCertificate.init(SecureCert),
          flags = socketFlags)
      else:
        HttpServer.create(initTAddress("127.0.0.1:8888"), flags = socketFlags)

    when defined accepts:
      echo "accepts"
      proc accepts() {.async, raises: [Defect].} =
        while true:
          try:
            let req = await server.accept()
            await req.handle()
          except CatchableError as exc:
            error "Transport error", exc = exc.msg

      asyncSpawn accepts()
    else:
      server.handler = handle
      server.start()

    trace "Server listening on ", data = $server.localAddress()
    echo "started"
    await server.join()

  waitFor(main())