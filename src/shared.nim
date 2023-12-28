import threading/channels, std/locks , store
from adapters/mux import Cid
export channels,Cid

var masterChannel* = newAsyncChannel[Cid](maxItems = 500)
masterChannel.open()


when helpers.hasThreadSupport:
    var peerConnectedlock*:Lock
    var peerConnected*{.guard:peerConnectedlock.}: bool = false
    initLock peerConnectedlock
else:
    var peerConnected*: bool = false

template lock*(a: Lock; body: untyped) =
    a.acquire()
    {.locks: [peerConnectedlock].}:
        try:
            body
        finally:
            a.release()

            
var publicStore* = newStore()
