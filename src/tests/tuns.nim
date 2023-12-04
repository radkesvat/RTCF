import tunnel, pretty, unittest2, strutils
import stew/byteutils

logScope:
    topic = "Test"

type MyAdapter* = ref object of Tunnel

    wrotestr :string
    writebuf: seq[char]


proc new*(t: typedesc[MyAdapter], name = "MyAdapter"): MyAdapter =
    trace "new MyAdapter"
    result = MyAdapter(name: name)
    result.writebuf = newSeqOfCap[char](1500)
    result.rv = newStringView(cap = 2000)

method write*(self: MyAdapter, rp: StringView, chain: Chains = default): Future[void] =
    info "Adapter write to socket", adapter = self.name, data = $rp

    self.wv = rp
    #wrote to socket
    self.wrotestr =  $self.wv

    self.wv.reset()

    result = newFuture[void]("write MyAdapter")
    result.complete()

method read*(self: MyAdapter, chain: Chains = default): Future[StringView] {.async.} =
    info "Adapter read from socket", adapter = self.name, data = self.wrotestr
    let ret = newFuture[StringView]("read MyAdapter")


    self.rv.reset()

    await sleepAsync(2)
    self.rv.write(self.wrotestr)
    
    return self.rv
    # sleepAsync(2000).addCallback do(u: pointer):
    #     ret.complete self.data
    # return ret

    # result = Container(data : data.toOpenArrayByte(0,data.high))
    # result = procCall read(Tunnel(self))


type Nimche = ref object of Tunnel
    mark: string

proc new*(t: typedesc[Nimche], name = "unnamed tunenl"): Nimche =
    trace "new Tunnel", name = "nimche"
    result = Nimche(name: name, hsize: 5)
    result.mark = " " & name & " "

method write*(self: Nimche, data: StringView, chain: Chains = default): Future[void] {.raises: [], gcsafe.} =
    writeChecks(self, data):
        copyMem(self.writeBuffer, addr self.mark[0], self.mark.len)

    trace "Appended ", header = (string.fromBytes(makeOpenArray(self.writeBuffer, byte, self.hsize))), result = ($data)

    procCall write(Tunnel(self), data)

method read*(self: Nimche, chain: Chains = default): Future[StringView] {.raises: [], gcsafe.} =
    let ret = newFuture[StringView]("read")
    var stream = procCall read(Tunnel(self))
    stream.addCallback proc(u: pointer) =
        var data = stream.value()
        readChecks(self, data):
            discard

        trace "extracted ", header = string.fromBytes(makeOpenArray(self.readBuffer, byte, self.hsize)), result = $data

        ret.complete data
    return ret

suite "Suite for testing basic tunnel":
    setup: discard
        # echo "run before each test"
        # bind iao
    teardown: discard
        # echo "run after each test"


    test "basic read write":
        proc run() {.async.} =
            var nc1: Nimche = Nimche.new(name = "nc1")
            var nc2: Nimche = Nimche.new(name = "nc2")
            var nc3: Nimche = Nimche.new(name = "nc3")
            var nc4: Nimche = Nimche.new(name = "nc4")
            nc1.chain(nc2).chain(nc3).chain(nc4).chain(MyAdapter.new())

            var write_data = "hallo"
            info "Data to send through tunnels", write_data
            var writeview = newStringView()
            writeview.write(write_data)
            info "View to send through tunnels", writeview
            await nc1.write(writeview)
            let read = $(await nc1.read())
            # print read
            check(read == write_data)
        waitFor run()
    test "what happens with 0 cap":
        proc run() {.async.} =
            var nc1: Nimche = Nimche.new(name = "nc1")
            var nc2: Nimche = Nimche.new(name = "nc2")
            var nc3: Nimche = Nimche.new(name = "nc3")
            var nc4: Nimche = Nimche.new(name = "nc4")
            nc1.chain(nc2).chain(nc3).chain(nc4).chain(MyAdapter.new())
            
            for i in 0..9:
                var write_data = "hallo"
                info "Data to send through tunnels", write_data
                var writeview = newStringView(cap = 0)
                writeview.write(write_data)
                info "View to send through tunnels", writeview
                await nc1.write(writeview)
                let read = $(await nc1.read())
                # print read
                check(read == write_data)
        waitFor run()
















