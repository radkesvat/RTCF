import threading/channels, std/isolation

proc test(chan: ptr Chan[string]) {.thread.} =
  var notSent = true
  while notSent:
    var msg = isolate("Hello")
    notSent = not chan[].trySend(msg)

var chan = newChan[string](elements = 1)
var t1: Thread[ptr Chan[string]]
var dest: string

createThread(t1, test, chan.addr)
chan.recv(dest)

t1.joinThread()