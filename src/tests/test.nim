import chronos, chronos/timer, threading/channels



proc fut():Future[int]{.async.}=
    await sleepAsync(5000)
    return 28
    
var futo = fut()
proc test(i:int){.async.} =
    await sleepAsync(7000)
    echo $(await futo)
     

for i in 0..10: asyncSpawn test(i)




runForever()