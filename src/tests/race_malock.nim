import benchy
import malebolgia / lockers

type mt = ref int
# var counter : mt = new mt
var results: Locker[mt]
results = initLocker  new mt

proc incCounter(i: int) {.thread.} =
    for j in 0 ..< i:
        lock results as counter:
            var local = counter[]
            local += 1
            counter[] = local

const N = 100000

proc main =
  var th1, th2: Thread[int]
  createThread(th1, incCounter, N)
  createThread(th2, incCounter, N)
  joinThreads(th1, th2)
  lock results as counter:
    echo N, ": ", counter[]
timeIt "run":
    main()



# result: ticketlocks lose so hard to std/locks in performance