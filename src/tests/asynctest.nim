import chronos,chronos/timer





proc c1: Future[void] =
    echo "Before sleep"
    var retFuture = newFuture[void]("chronos.sleepgAsync(Duration)")

    proc completion(data: pointer) {.gcsafe.} =
        # if not(retFuture.finished()):
        #     retFuture.complete()
        echo "complete"

    proc cancellation(udata: pointer) {.gcsafe.} =
        echo "cancel"
        # if not(retFuture.finished()):
        #     clearTimer(timer)

    retFuture.callback = completion
    retFuture.cancelCallback = cancellation

    sleepAsync(1000).callback=proc(udata:pointer)= retFuture.fail((ref ResourceExhaustedError)(msg: "shit"))
    # timer = setTimer(moment, completion, cast[pointer](retFuture))
    return retFuture

proc c2 {.async.} =
    try:
        await c1()
        echo "After sleep c2" # not reach due to cancellation
    except CancelledError as exc:
        echo "We got cancelled! c2"
    except:
        echo "anything else?"
    finally:
        echo "salam"
#   echo "Never reached, since the CancelledError got re-raised"

let work = c2()

runForever()
