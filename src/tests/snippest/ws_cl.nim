## nim-websock
## Copyright (c) 2021 Status Research & Development GmbH
## Licensed under either of
##  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
##  * MIT license ([LICENSE-MIT](LICENSE-MIT))
## at your option.
## This file may not be copied, modified, or distributed except according to
## those terms.

import pkg/[
  chronos,
  chronicles,
  stew/byteutils]

import websock/websock

proc main() {.async.} =
  let ws = when defined tls:
    await WebSocket.connect(
        "127.0.0.1:8889",
        path = "/wss",
        secure = true,
        flags = {TLSFlags.NoVerifyHost, TLSFlags.NoVerifyServerName})
    else:
      await WebSocket.connect(
        "127.0.0.1:8888",
        path = "/ws")

  trace "Websocket client: ", State = ws.readyState

  let reqData = "Hello Server"
  while true:
    try:
      await ws.send(reqData)
      let buff = await ws.recv()
      if buff.len <= 0:
        break

      let dataStr = string.fromBytes(buff)
      trace "Server Response: ", data = dataStr

      doAssert dataStr == reqData
      break
    except WebSocketError as exc:
      error "WebSocket error:", exception = exc.msg
      raise exc

    await sleepAsync(100.millis)

  # close the websocket
  await ws.close()

waitFor(main())