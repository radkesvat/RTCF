import tables,chronos




type TimerDispatcher* = ref object
    handles: Table[int64,proc(){.closure,raises: [].}]


proc register*(self:TimerDispatcher,cb: proc(){.closure,raises: [].}):int64=
    var key = Moment.now().epochNanoSeconds()
    if self.handles.hasKeyOrPut(key,cb):
        # this is impossible since tested many times the hardest possible cases
        fatal "Double key in TimerDispatcher!"; quit(1)
    return key


proc unregister*(self:TimerDispatcher,key:int64)=
    self.handles.del(key)



proc start*(self:TimerDispatcher,delay:Duration){.async: (raises: []).}=
    while true:
        for (k,v) in self.handles.pairs:
            v()
        try:
            await sleepAsync(delay)
        except:
            fatal "cancelling TimerDispatcher...? why?"; quit(1)