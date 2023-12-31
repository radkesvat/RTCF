import chronos, chronos/timer, threading/channels


var chan = newAsyncChannel[int](10)
chan.open()

proc listen(){.async.}=
    echo $(await chan.recv())

proc destroy(){.async.}=
    {.cast(raises: []), gcsafe.}:

        await sleepAsync(4.seconds)
        chan.close()
        echo "closed1"
        await sleepAsync(4.seconds)
        chan.close()
        echo "closed2"
        await sleepAsync(4.seconds)


asyncSpawn listen()
asyncSpawn destroy()
runForever()
        