import tables,chronos




type 
    CallBack = proc(){.closure,raises: [].}
    TimerDispatcher* = ref object
        handles: Table[int64,CallBack]


proc register*(self:TimerDispatcher,cb:CallBack):int64=
    var key = Moment.now().epochNanoSeconds()
    if self.handles.hasKeyOrPut(key,cb):
        # this is impossible since tested many times the hardest possible cases
        fatal "Double key in TimerDispatcher!"; quit(1)
    return key


proc unregister*(self:TimerDispatcher,key:int64)=
    self.handles.del(key)



proc start*(self:TimerDispatcher,delay:Duration){.async: (raises: []).}=
    while true:
        var funcs = newSeqOfCap[CallBack](cap = self.handles.len)
        
        for (k,v) in self.handles.pairs:
            funcs.add v
        for v in funcs: v()
        try:
            await sleepAsync(delay)
        except:
            fatal "cancelling TimerDispatcher...? why?"; quit(1)