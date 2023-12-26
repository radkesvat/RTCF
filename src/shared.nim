import threading/channels
from adapters/mux import Cid
export channels,Cid

var masterChannel* = newAsyncChannel[Cid](maxItems = 500)
masterChannel.open()