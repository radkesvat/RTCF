import strutils


import chronos/[handles, transport,threadsync]

const hasThreadSupport = compileOption("threads")
when hasThreadSupport:
  import locks


type
  RawAsyncChannelImpl {.pure, final.} = object
    rd, wr, count, mask: int
    maxItems: int
    refCount: int
    data: ptr UncheckedArray[byte]
    when hasThreadSupport:
      lock: Lock
    eventNotEmpty: ThreadSignalPtr
    eventNotFull: ThreadSignalPtr

  RawAsyncChannel = ptr RawAsyncChannelImpl
  AsyncChannel*[Msg] = RawAsyncChannel
  AsyncChannelError* = object of CatchableError

proc initLocks(rchan: RawAsyncChannel) {.inline.} =
  ## Initialize and create OS locks.
  when hasThreadSupport:
    initLock(rchan.lock)
  else:
    discard
  rchan.eventNotEmpty = ThreadSignalPtr.new().value()
  if rchan.maxItems > 0:
    rchan.eventNotFull = ThreadSignalPtr.new().value()

proc releaseLock(rchan: RawAsyncChannel) {.inline.} 

proc deinitLocks(rchan: RawAsyncChannel) {.inline.} =
  ## Deinitialize and close OS locks.


  close(rchan.eventNotEmpty).value()
  if rchan.maxItems > 0:
    close(rchan.eventNotFull).value()
  rchan.releaseLock()

  when hasThreadSupport:
    deinitLock(rchan.lock)
  else:
    discard

proc acquireLock(rchan: RawAsyncChannel) {.inline.} =
  ## Acquire lock in multi-threaded mode and do nothing in
  ## single-threaded mode.
  when hasThreadSupport:
    acquire(rchan.lock)
  else:
    discard

proc releaseLock(rchan: RawAsyncChannel) {.inline.} =
  ## Release lock in multi-threaded mode and do nothing in
  ## single-threaded mode.
  when hasThreadSupport:
    release(rchan.lock)
  else:
    discard

proc newAsyncChannel*[Msg](maxItems: int = -1): AsyncChannel[Msg] =
  ## Create new AsyncChannel[Msg] with internal queue size ``maxItems``.
  ##
  ## If ``maxItems <= 0`` (default value), then queue size is unlimited.
  let loop = getThreadDispatcher()
  result = cast[AsyncChannel[Msg]](allocShared(sizeof(RawAsyncChannelImpl)))
  result.mask = -1
  if maxItems <= 0:
    result.maxItems = -1
  else:
    result.maxItems = maxItems
  result.count = 0
  result.wr = 0
  result.rd = 0
  result.refCount = 0
  result.data = cast[ptr UncheckedArray[byte]](0)
  result.initLocks()

proc raiseChannelClosed() {.inline.} =
  var err = newException(AsyncChannelError, "Channel closed or not opened")
  raise err

proc raiseChannelFailed() {.inline.} =
  var err = newException(AsyncChannelError, "Channel synchronization failed")
  raise err

proc open*[Msg](chan: AsyncChannel[Msg]) =
  ## Open channel ``chan``.
  let loop = getThreadDispatcher()
  chan.acquireLock()
  inc(chan.refCount)
  chan.releaseLock()

proc close*[Msg](chan: AsyncChannel[Msg]) =
  ## Close channel ``chan``.
  chan.acquireLock()
  if chan.refCount == 0:
    assert chan.count == 0
    if not(isNil(chan.data)):
      deallocShared(cast[pointer](chan.data))
    chan.deinitLocks()
    deallocShared(cast[pointer](chan))
  else:
    dec(chan.refCount)
    chan.releaseLock()


proc `$`*[Msg](chan: AsyncChannel[Msg]): string =
  ## Dump channel ``chan`` debugging information as string.
  chan.acquireLock()
  result = "channel 0x" & toHex(cast[uint](chan)) & " ("
  result.add("eventNotEmpty = 0x" & toHex(cast[uint](chan.eventNotEmpty)))
  result.add(", eventNotFull = 0x" & toHex(cast[uint](chan.eventNotFull)))
  result.add(", rd = " & $chan.rd)
  result.add(", wr = " & $chan.wr)
  result.add(", count = " & $chan.count)
  result.add(", mask = 0x" & toHex(chan.mask))
  result.add(", data = 0x" & toHex(cast[uint](chan.data)))
  result.add(", maxItems = " & $chan.maxItems)
  result.add(", refCount = " & $chan.refCount)
  result.add(")")
  chan.releaseLock()

proc rawSend(rchan: RawAsyncChannel, pbytes: pointer, nbytes: int) =
  var cap = rchan.mask + 1
  if rchan.count >= cap:
    if cap == 0: cap = 1
    var n = cast[ptr UncheckedArray[byte]](allocShared0(cap * 2 * nbytes))
    var z = 0
    var i = rchan.rd
    var c = rchan.count

    while c > 0:
      dec(c)
      copyMem(addr(n[z * nbytes]), addr(rchan.data[i * nbytes]), nbytes)
      i = (i + 1) and rchan.mask
      inc(z)

    if not isNil(rchan.data):
      deallocShared(rchan.data)

    rchan.data = n
    rchan.mask = (cap * 2) - 1
    rchan.wr = rchan.count
    rchan.rd = 0

  copyMem(addr(rchan.data[rchan.wr * nbytes]), pbytes, nbytes)
  inc(rchan.count)
  rchan.wr = (rchan.wr + 1) and rchan.mask

proc send*[Msg](chan: AsyncChannel[Msg], msg: Msg, unregister:bool = false) {.async.} =
  ## Send message ``msg`` over channel ``chan``. This procedure will wait if
  ## internal channel queue is full.
  chan.acquireLock()
  if chan.refCount == 0:
    chan.releaseLock()
    raiseChannelClosed()

  if chan.maxItems > 0:
    # Wait until count is less then `maxItems`.
    while chan.count >= chan.maxItems:
      chan.releaseLock()
      # let failed = 
      #   try: 
      #     await chan.eventNotFull.wait()
      #     false
      #   except: 
      #     true
      await chan.eventNotFull.wait()
      chan.acquireLock()
      # if failed:
      #   raiseChannelFailed()
         
  rawSend(chan, unsafeAddr msg, sizeof(Msg))
  discard chan.eventNotEmpty.fireSync()

  if unregister:
    chan.eventNotEmpty.unRegisterThread()
    if chan.maxItems > 0:
      chan.eventNotFull.unRegisterThread()

  chan.releaseLock()

proc sendSync*[Msg](chan: AsyncChannel[Msg], msg: Msg) =
  ## Immediately send message ``msg`` over channel ``chan``. This procedure will
  ## block until internal channel's queue is full.
  chan.acquireLock()
  try:
    if chan.refCount == 0:
      raiseChannelClosed()

    if chan.maxItems > 0:
      # Wait until count is less then `maxItems`.
      while chan.count >= chan.maxItems:
        chan.releaseLock()
        let res = chan.eventNotFull.waitSync(InfiniteDuration).tryGet()
        chan.acquireLock()
        if not res:
          raiseChannelFailed()

    rawSend(chan, unsafeAddr msg, sizeof(Msg))
    discard chan.eventNotEmpty.fireSync()

  finally:
    chan.releaseLock()

proc rawRecv(rchan: RawAsyncChannel, pbytes: pointer, nbytes: int) {.inline.} =
  doAssert(rchan.count > 0)
  dec(rchan.count)
  copyMem(pbytes, addr rchan.data[rchan.rd * nbytes], nbytes)
  rchan.rd = (rchan.rd + 1) and rchan.mask

proc recv*[Msg](chan: AsyncChannel[Msg]): Future[Msg] {.async.} =
  ## Wait for message ``Msg`` in channel ``chan`` asynchronously and receive
  ## it when it become available.
  var rmsg: Msg
  chan.acquireLock()
  if chan.refCount == 0:
    chan.releaseLock()
    raiseChannelClosed()

  while chan.count <= 0:
    chan.releaseLock()
    await chan.eventNotEmpty.wait()
    # let failed = 
    #   try: 
    #     await chan.eventNotEmpty.wait()
    #     false
    #   except : 
    #     true
    
    chan.acquireLock()
    # if failed:
    #   raiseChannelFailed()

  rawRecv(chan, addr rmsg, sizeof(Msg))
  result = rmsg

  if chan.maxItems > 0:
    discard chan.eventNotFull.fireSync()

  chan.releaseLock()

proc recvSync*[Msg](chan: AsyncChannel[Msg]): Msg =
  ## Blocking receive message ``Msg`` from channel ``chan``.
  chan.acquireLock()
  try:
    if chan.refCount == 0:
      raiseChannelClosed()

    while chan.count <= 0:
      chan.releaseLock()
      let res = chan.eventNotEmpty.waitSync(InfiniteDuration).tryGet
      chan.acquireLock()
      if not res:
        raiseChannelFailed()

    rawRecv(chan, addr result, sizeof(Msg))

    if chan.maxItems > 0:
      discard chan.eventNotFull.fireSync()

  finally:
    chan.releaseLock()



proc trySend*[Msg](chan: AsyncChannel[Msg], msg: Msg):bool =
  ## Immediately send message ``msg`` over channel ``chan``. This procedure will
  ## block until internal channel's queue is full.
  chan.acquireLock()
  try:
    if chan.refCount == 0:
      raiseChannelClosed()

    if chan.maxItems > 0:
      # Wait until count is less then `maxItems`.
      if chan.count >= chan.maxItems:
        return false

    rawSend(chan, unsafeAddr msg, sizeof(Msg))
    discard chan.eventNotEmpty.fireSync()
    return true

  finally:
    chan.releaseLock()






proc drain*[Msg](chan: AsyncChannel[Msg],consumer: proc(arg:MSG):void) =
  ## Blocking receive message ``Msg`` from channel ``chan``.
  chan.acquireLock()
  var buf:Msg
  try:
    when not defined(release): assert chan.refCount == 0
    #   raiseChannelClosed()

    while (chan.count > 0):
      rawRecv(chan, addr buf, sizeof(Msg))
      consumer(buf)

    chan.eventNotEmpty.unRegisterThread()
    if chan.maxItems > 0:
      chan.eventNotFull.unRegisterThread()
  finally:
    chan.releaseLock()




proc dataLeft*[Msg](chan: AsyncChannel[Msg]):int =
  chan.acquireLock()
  result = chan.count
  chan.releaseLock()

proc unregister*[Msg](chan: AsyncChannel[Msg]) =
  chan.acquireLock()

  chan.eventNotEmpty.unRegisterThread()
  if chan.maxItems > 0:
    chan.eventNotFull.unRegisterThread()


  chan.releaseLock()


proc hasListener*[Msg](chan: AsyncChannel[Msg]): bool =
  chan.acquireLock()
  try:
    return chan.refCount > 0
  finally:
    chan.releaseLock()