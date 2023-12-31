

import std/[cpuinfo, locks, strutils, os,isolation, exitprocs]
import chronos, chronos/threadsync, pretty
import system / ansi_c
import threading/channels

let numProcs = 2
let address = initTAddress("127.0.0.1", 8888.Port)
var mylock: Lock
var server{.guard: mylock.}: Isolated[StreamServer] 

proc run(id: int) {.thread, gcsafe.} =
    discard
    # proc accepts() {.async, raises: [Defect].} =
    #     while true:
    #         withLock mylock:
    #             server.sock.register()
    #             try:
    #                 let req = await server.accept()
    #                 print "Connected client: ", req.remoteAddress(), id
    #             except CatchableError as exc:
    #                 error "Transport error", exc = exc.msg
    #             server.sock.unregister()

    # asyncSpawn accepts()
    # runForever()

initLock mylock
withLock mylock:
    server = isolate createStreamServer(address, flags = {ServerFlags.TcpNoDelay, ServerFlags.ReuseAddr})
    server.sock.unregister()

var threads = newSeq[Thread[int]](numProcs)
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
