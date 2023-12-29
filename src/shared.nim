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

template lockpeerConnected*(body: untyped) =
    when helpers.hasThreadSupport:
        peerConnectedlock.acquire()
        {.locks: [peerConnectedlock].}:
            try:
                body
            finally:
                peerConnectedlock.release()
    else:
        body


            
var publicStore* = newStore()
