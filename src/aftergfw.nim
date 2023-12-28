import std/[cpuinfo, locks, strutils, os, osproc]
import std/exitprocs
import globals, chronos
import system/ansi_c except SIGTERM
from globals import nil
import beforeGFW/[left, right]

logScope:
    topic = "Kharej"

var cloudflareIps = @[
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22"
]

when NimMajor >= 2 and hasThreadSupport:
    when defined(posix):
        from posix import pthread_cancel
    else:
        from std/private/threadtypes import terminateThread

    proc exitMultiThread(threads: sink seq[Thread[int]]) =
        when NimMajor >= 2 :
            when defined(posix):
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
        else:
            discard




proc rightThread(threadID: int){.thread.} =
    warn "RightThread spawend"
    var disp = getThreadDispatcher()
    waitFor right.run(threadID)


proc leftThread(threadID: int){.thread.} =
    warn "LeftThread spawend"
    var disp = getThreadDispatcher()
    waitFor left.run(threadID)


proc main() =

    
    proc singlethread() =
        asyncSpawn left.run(1)
        asyncSpawn right.run(1)
        runForever()

    when hasThreadSupport:

        proc mutithread() =
            var threads_left: int = globals.threadsCount.int
            var threads = newSeqOfCap[Thread[int]](cap = 20)
            var i = 0
            while threads_left > 0:
                threads.setLen(threads.len+2)
                # TODO: Set the scheduling policy to SCHED_FIFO (real-time)
                createThread(threads[i], leftThread, i+1);  inc i
                createThread(threads[i], rightThread, i+1); inc i
                threads_left -= 2

            info "Waiting for spawend threads"
            joinThreads(threads)
            warn "All spawend threads have finished"
            exitMultiThread(threads)

        doAssert globals.threadsCount >= 1

        if globals.threadsCount == 1:
            singlethread()
        else:
            mutithread()

    else:
        doAssert globals.threadsCount == 1
        singlethread()



proc start* = main()



