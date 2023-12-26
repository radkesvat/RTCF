import unittest2, tunnel, store
import tunnels/udp


type
    TestAdapter* = ref object of Adapter
        store: Store


const udpflag*: char = char(0b00000010)


proc new*(t: typedesc[TestAdapter], name: string = "TestAdapter", store: Store): TestAdapter =
    result = new TestAdapter
    result.store = store
    procCall init(Adapter(result), name, hsize = 0)
    trace "Initialized", name

method write*(self: TestAdapter, rp: StringView, chain: Chains = default): Future[void] {.async.} =
    var index {.global.} = 0
    var sv = self.store.pop()
    case index:
        of 0:
            check $sv == (udpflag & "salam")

        of 1:
            check $sv == (udpflag & "farmande")
        else:
            discard

    inc index

method read*(self: TestAdapter, bytes: int, chain: Chains = default): Future[StringView] {.async.} =
    var index {.global.} = 0
    var sv = self.store.pop()

    var res: StringView = case index:
        of 0:
            sv.write(udpflag & "1234"); sv

        of 1:
            sv.write(udpflag & "salam farmande"); sv
        else:
            nil
    inc index
    return res

proc startTest(self: TestAdapter){.async.} =
    var sv = self.store.pop()
    {.cast(raises: []).}:
        trace "starting"
        trace "doing write tests"
        sv.write("salam"); await procCall write(Tunnel(self), sv); sv = self.store.pop()
        sv.write("farmande"); await procCall write(Tunnel(self), sv); sv = self.store.pop()
        assert $(await procCall read(Tunnel(self), 4)) == "1234"
        assert $(await procCall read(Tunnel(self), 14)) == "salam farmande"
        trace "end"

method signal*(self: TestAdapter, dir: SigDirection, sig: Signals, chain: Chains = default) =
    # if sig == start: asyncSpawn self.start()
    if sig == close or sig == stop:
        quit("stop sig?")
    if sig == breakthrough: doAssert self.stopped, "break through signal while still running?"
    procCall signal(Tunnel(self), dir, sig, chain) #only for test





suite "Suite for testing udp Tunnel":

    test "Test basic read write":
        proc test(){.async.} =
            {.cast(raises: []).}:
                var pub_store = Store.new()
                var a1 = TestAdapter.new(store = pub_store)
                var a2 = TestAdapter.new(store = pub_store)
                var p = newUdpTunnel(store = pub_store)
                a1.chain(p).chain(a2)
                a1.signal(both, start)
                await a1.startTest()
        waitfor test()

quit()
