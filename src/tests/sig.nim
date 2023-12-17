import std/[cpuinfo, locks, strutils,os]
import chronos/unittest2/asynctests
import chronos/threadsync
import threading/channels

type Arg = tuple
    id:int
    sig:ThreadSignalPtr

let numProcs = 2
var signal = ThreadSignalPtr.new().tryGet()

proc run(arg: Arg) {.thread.} =
    while true:
        assert arg.sig.waitSync().tryGet()
        echo "recv by thread: ",arg.id
                                        
var threads = newSeq[Thread[Arg]](numProcs)
for i in 0 ..< numProcs:
    createThread(threads[i], run, (i+1,signal))

while true:
    echo "fire"
    assert signal.fireSync().tryGet()

    sleep(1000)

joinThreads(threads)
 