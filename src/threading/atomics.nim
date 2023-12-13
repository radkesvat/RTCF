#
#
#            Nim's Runtime Library
#        (c) Copyright 2021 Nim Contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Types and operations for atomic operations and lockless algorithms.
runnableExamples("--threads:on"):
  # Atomic
  var loc: Atomic[int]
  loc.store(4)
  assert loc.load == 4
  loc.store(2)
  assert loc.load(Relaxed) == 2
  loc.store(9)
  assert loc.load(Acquire) == 9
  loc.store(0, Release)
  assert loc.load == 0

  assert loc.exchange(7) == 0
  assert loc.load == 7

  var expected = 7
  assert loc.compareExchange(expected, 5, Relaxed, Relaxed)
  assert expected == 7
  assert loc.load == 5

  assert not loc.compareExchange(expected, 12, Relaxed, Relaxed)
  assert expected == 5
  assert loc.load == 5

  assert loc.fetchAdd(1) == 5
  assert loc.fetchAdd(2) == 6
  assert loc.fetchSub(3) == 8

  loc.atomicInc(1)
  assert loc.load == 6

when not compileOption("threads"):
  {.error: "This module requires --threads:on compilation flag".}

type
  Ordering* {.pure.} = enum
    ## Specifies how non-atomic operations can be reordered around atomic
    ## operations.
    Relaxed
      ## No ordering constraints. Only the atomicity and ordering against
      ## other atomic operations is guaranteed.
    Consume
      ## This ordering is currently discouraged as it's semantics are
      ## being revised. Acquire operations should be preferred.
    Acquire
      ## When applied to a load operation, no reads or writes in the
      ## current thread can be reordered before this operation.
    Release
      ## When applied to a store operation, no reads or writes in the
      ## current thread can be reorderd after this operation.
    AcqRel
      ## When applied to a read-modify-write operation, this behaves like
      ## both an acquire and a release operation.
    SeqCst
      ## Behaves like Acquire when applied to load, like Release when
      ## applied to a store and like AcquireRelease when applied to a
      ## read-modify-write operation.
      ## Also guarantees that all threads observe the same total ordering
      ## with other SeqCst operations.

type
  Atomic*[T: AtomType] = distinct T ## An atomic object with underlying type `T`.

proc `=copy`*[T](dst: var Atomic[T]; src: Atomic[T]) =
  atomicStoreN(addr T(dst), T(src), AtomicSeqCst)

proc `=sink`*[T](dst: var Atomic[T]; src: Atomic[T]) =
  atomicStoreN(addr T(dst), T(src), AtomicSeqCst)

proc load*[T](location: var Atomic[T]; order: Ordering = SeqCst): T =
  ## Atomically obtains the value of the atomic object.
  atomicLoadN(addr T(location), AtomMemModel(order))

proc store*[T](location: var Atomic[T]; desired: T; order: Ordering = SeqCst) =
  ## Atomically replaces the value of the atomic object with the `desired`
  ## value.
  atomicStoreN(addr T(location), desired, AtomMemModel(order))

proc exchange*[T](location: var Atomic[T]; desired: T;
    order: Ordering = SeqCst): T =
  ## Atomically replaces the value of the atomic object with the `desired`
  ## value and returns the old value.
  atomicExchangeN(addr T(location), desired, AtomMemModel(order))

proc compareExchange*[T](location: var Atomic[T]; expected: var T; desired: T;
    order: Ordering = SeqCst): bool =
  ## Atomically compares the value of the atomic object with the `expected`
  ## value and performs exchange with the `desired` one if equal or load if
  ## not. Returns true if the exchange was successful.
  atomicCompareExchangeN(addr T(location), addr expected, desired,
      false, AtomMemModel(order), AtomMemModel(order))

proc compareExchange*[T](location: var Atomic[T]; expected: var T; desired: T;
    success, failure: Ordering): bool =
  ## Same as above, but allows for different memory orders for success and
  ## failure.
  atomicCompareExchangeN(addr T(location), addr expected, desired,
      false, AtomMemModel(success), AtomMemModel(failure))

proc compareExchangeWeak*[T](location: var Atomic[T]; expected: var T;
    desired: T; order: Ordering = SeqCst): bool =
  ## Same as above, but is allowed to fail spuriously.
  atomicCompareExchangeN(addr T(location), addr expected, desired,
      true, AtomMemModel(order), AtomMemModel(order))

proc compareExchangeWeak*[T](location: var Atomic[T]; expected: var T;
    desired: T; success, failure: Ordering): bool =
  ## Same as above, but allows for different memory orders for success and
  ## failure.
  atomicCompareExchangeN(addr T(location), addr expected, desired,
      true, AtomMemModel(success), AtomMemModel(failure))

# Numerical operations

proc fetchAdd*[T: SomeInteger](location: var Atomic[T]; value: T;
    order: Ordering = SeqCst): T =
  ## Atomically adds a `value` to the atomic integer and returns the
  ## original value.
  atomicFetchAdd(addr T(location), value, AtomMemModel(order))

proc fetchSub*[T: SomeInteger](location: var Atomic[T]; value: T;
    order: Ordering = SeqCst): T =
  ## Atomically subtracts a `value` to the atomic integer and returns the
  ## original value.
  atomicFetchSub(addr T(location), value, AtomMemModel(order))

proc fetchAnd*[T: SomeInteger](location: var Atomic[T]; value: T;
    order: Ordering = SeqCst): T =
  ## Atomically replaces the atomic integer with it's bitwise AND
  ## with the specified `value` and returns the original value.
  atomicFetchAnd(addr T(location), value, AtomMemModel(order))

proc fetchOr*[T: SomeInteger](location: var Atomic[T]; value: T;
    order: Ordering = SeqCst): T =
  ## Atomically replaces the atomic integer with it's bitwise OR
  ## with the specified `value` and returns the original value.
  atomicFetchOr(addr T(location), value, AtomMemModel(order))

proc fetchXor*[T: SomeInteger](location: var Atomic[T]; value: T;
    order: Ordering = SeqCst): T =
  ## Atomically replaces the atomic integer with it's bitwise XOR
  ## with the specified `value` and returns the original value.
  atomicFetchXor(addr T(location), value, AtomMemModel(order))

proc atomicInc*[T: SomeInteger](location: var Atomic[T];
    value: T = 1) {.inline.} =
  ## Atomically increments the atomic integer by some `value`.
  discard location.fetchAdd(value)

proc atomicDec*[T: SomeInteger](location: var Atomic[T];
    value: T = 1) {.inline.} =
  ## Atomically decrements the atomic integer by some `value`.
  discard location.fetchSub(value)

proc `+=`*[T: SomeInteger](location: var Atomic[T]; value: T) {.inline.} =
  ## Atomically increments the atomic integer by some `value`.
  discard location.fetchAdd(value)

proc `-=`*[T: SomeInteger](location: var Atomic[T]; value: T) {.inline.} =
  ## Atomically decrements the atomic integer by some `value`.
  discard location.fetchSub(value)
