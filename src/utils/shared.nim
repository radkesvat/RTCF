import threading/[channels], store
when helpers.hasThreadSupport:
    import threading/atomics
from adapters/mux import Cid
export channels, Cid

var masterChannel* = newAsyncChannel[Cid](maxItems = 500)
masterChannel.open()


when helpers.hasThreadSupport:
    var peerConnected: Atomic[bool]
    peerConnected.store(false, Ordering.Relaxed)

else:
    var peerConnected: bool = false


template isPeerConnected*(): bool =
    when helpers.hasThreadSupport: peerConnected.load(Ordering.Relaxed)
    else: peerConnected

template setIsPeerConnected*(val: bool) =
    when helpers.hasThreadSupport: peerConnected.store(val, Ordering.Relaxed)
    else: peerConnected = val

var publicStore* = newStore()
