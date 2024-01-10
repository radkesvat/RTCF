import chronos, chronos/timer, threading/channels

var chan = newAsyncChannel[int]()
chan.open

proc read(){.async.}=
    echo $(await chan.recv())

proc read2(){.async.}=
    echo $(await chan.recv())

proc start(){.async.}=
    await sleepAsync(1200)
    chan.sendSync(42)


asyncSpawn read()
var f = read2()
# cancelSoon f
asyncSpawn start()



runForever()