import tables, chronos,tunnel




type
    Entry = tuple[obj:Tunnel,cb :  proc(p:Tunnel){.raises: [].}]

    TimerDispatcher* = ref object
        handles: Table[int64, Entry]


proc register*(self: TimerDispatcher,obj:Tunnel,cb:proc(p:Tunnel){.raises: [].}): int64 =
    var key = Moment.now().epochNanoSeconds()
    if self.handles.hasKeyOrPut(key, (obj,cb)):
        # this is impossible since tested many times the hardest possible cases
        fatal "Double key in TimerDispatcher!"; quit(1)
    return key


proc unregister*(self: TimerDispatcher, key: int64) =
    self.handles.del(key)



proc start*(self: TimerDispatcher, delay: Duration){.async: (raises: []).} =
    while true:
        block action:
            var funcs = newSeqOfCap[Entry](cap = self.handles.len)

            for (k, v) in self.handles.pairs:
                funcs.add v
            
                    
            for v in funcs: {.cast(gcsafe).}: v.cb(v.obj)

        try:
            await sleepAsync(delay)
        except:
            fatal "cancelling TimerDispatcher...? why?"; quit(1)
