import benchy
import malebolgia / ticketlocks

type mt = ref int
var lock: TicketLock
var counter : mt = new mt

proc incCounter(i: int) {.thread.} =
    for j in 0 ..< i:
        withLock lock:
            var local = counter[]
            local += 1
            counter[] = local

const N = 100000

proc main =
  var th1, th2: Thread[int]
  lock = initTicketLock()
  createThread(th1, incCounter, N)
  createThread(th2, incCounter, N)
  joinThreads(th1, th2)

timeIt "run":
    main()
    echo N, ": ", counter[]


# result: ticketlocks lose so hard to std/locks in performance