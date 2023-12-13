
import std/[cpuinfo, locks, strutils, isolation, os]
import benchy, pretty

var lock: Lock
var bytes: seq[byte]

proc init() =
    initLock lock
    bytes = newSeq[byte](len = 100)
    for i in 0..99: bytes[i] = byte i


proc worker(arg:Isolated[seq[byte]]) {.thread.} =
    for i in 0 ..< 100:
        withLock lock:
            let e = extract arg
            print e


proc main =
    init()
    var th1, th2: Thread[seq[byte]]
    var iso = isolate bytes
    createThread(th1, worker, iso)
    createThread(th2, worker, iso)
    joinThreads(th1, th2)

timeIt "run":
    main()
    # echo N, ": ", counter[]
