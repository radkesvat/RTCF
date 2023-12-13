#
#
#            Nim's Runtime Library
#        (c) Copyright 2021 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.

## Wait groups for Nim.

runnableExamples:

  var data: array[10, int]
  var wg = createWaitGroup()

  proc worker(i: int) =
    data[i] = 42
    wg.leave()

  var threads: array[10, Thread[int]]
  wg.enter(10)
  for i in 0..<10:
    createThread(threads[i], worker, i)

  wg.wait()
  for x in data:
    assert x == 42

  joinThreads(threads)


import std / [locks]

type
  WaitGroup* = object
    ## A `WaitGroup` is a synchronization object that can be used to `wait` until
    ## all workers have completed.
    c: Cond
    L: Lock
    runningTasks: int

when defined(nimAllowNonVarDestructor):
  proc `=destroy`(b: WaitGroup) {.inline.} =
    let x = addr(b)
    deinitCond(x.c)
    deinitLock(x.L)
else:
  proc `=destroy`(b: var WaitGroup) {.inline.} =
    deinitCond(b.c)
    deinitLock(b.L)

proc `=copy`(dest: var WaitGroup; src: WaitGroup) {.error.}
proc `=sink`(dest: var WaitGroup; src: WaitGroup) {.error.}

proc createWaitGroup*(): WaitGroup =
  result = default(WaitGroup)
  initCond(result.c)
  initLock(result.L)

proc enter*(b: var WaitGroup; delta: Natural = 1) {.inline.} =
  ## Tells the `WaitGroup` that one or more workers (the `delta` parameter says
  ## how many) "entered", which means to increase the counter that counts how
  ## many workers to wait for.
  acquire(b.L)
  inc b.runningTasks, delta
  release(b.L)

proc leave*(b: var WaitGroup) {.inline.} =
  ## Tells the `WaitGroup` that one worker has finished its task.
  acquire(b.L)
  if b.runningTasks > 0:
    dec b.runningTasks
    if b.runningTasks == 0:
      broadcast(b.c)
  release(b.L)

proc wait*(b: var WaitGroup) =
  ## Waits until all workers have completed.
  acquire(b.L)
  while b.runningTasks > 0:
    wait(b.c, b.L)
  release(b.L)
