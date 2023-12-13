

import std/[cpuinfo, locks, strutils, os,locks]
import chronos/unittest2/asynctests
import chronos/threadsync
import std/exitprocs
import system / ansi_c


#returns logical cores which each ``can`` run a thread
let numProcs = 8
var mylock:Lock


proc run(arg: int) {.thread.} =
    proc echoundwait(){.async.} =
        mylock.acquire()
        echo "Hi form " & $arg & "."
        await sleepAsync(1.seconds)
        mylock.release()
    discard echoundwait()

    waitFor(sleepAsync(2000))

var threads = newSeq[Thread[int]](numProcs)
initLock mylock
for i in 0 ..< numProcs:
    createThread(threads[i], run, i+1)



joinThreads(threads)
 
when NimMajor >= 2:
    when defined(posix):
        from posix import pthread_cancel
        
        addExitProc(proc() =
            for thr in threads:
                when compiles(pthread_cancel(thr.sys)):
                    discard pthread_cancel(thr.sys)
                if not isNil(thr.core):
                    when defined(gcDestructors):
                        c_free(thr.core)
                    else:
                        deallocShared(thr.core)
        )
    else:
        from std/private/threadtypes import terminateThread
        addExitProc(proc() =
            for thr in threads:
                when compiles(terminateThread(thr.sys, 1'i32)):
                    discard terminateThread(thr.sys, 1'i32)
                if not isNil(thr.core):
                    when defined(gcDestructors):
                        c_free(thr.core)
                    else:
                        deallocShared(thr.core)
        )