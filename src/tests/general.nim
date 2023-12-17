import pretty,sugar,rope,strutils,chronos
import stew/byteutils,threading/channels
import chronos/threadsync,cpuinfo


#returns logical cores which each ``can`` run a thread
let numProcs = countProcessors() 
var chan : Chan[int] = newChan[int]()

proc run(arg: int) {.thread.} =
    while true:
        cpuRelax()
                                        
var threads = newSeq[Thread[int]](numProcs)
for i in 0 ..< numProcs:
    createThread(threads[i], run, i+1)




joinThreads(threads)
 