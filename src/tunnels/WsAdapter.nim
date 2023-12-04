import tunnel


type WsAdapter* = ref object of Tunnel
    discard

method write*(self: WsAdapter, data: Rope) =
    echo "write to WsAdapter", self.name
    echo "data = ", $data

method read*(self: WsAdapter): Rope =
    echo "read from WsAdapter", self.name
    echo "data = salam"
    result = rope "salam"


proc new*(t:typedesc[WsAdapter], name = "websocket Adapter"):WsAdapter =
    result = WsAdapter()
    result.name = name
   
proc conenct*(address)=

