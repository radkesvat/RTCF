import tunnel, pretty, unittest2, strutils
import stew/byteutils

logScope:
    topic = "Test"

type MyAdapter* = ref object of Tunnel
    wrotestr :string


proc new*(t: typedesc[MyAdapter], name = "MyAdapter"): MyAdapter =
    trace "new MyAdapter"
    result = MyAdapter(name: name)
    result.rv = newStringView(cap = 2000)

method write*(self: MyAdapter, rp: StringView, chain: Chains = default): Future[void] {.async.} =
    info "Adapter write to socket", adapter = self.name, data = $rp

    self.wv = rp
    #wrote to socket
    await sleepAsync(2)
    self.wrotestr =  $self.wv

    self.wv.reset()

    

method read*(self: MyAdapter, chain: Chains = default): Future[StringView] {.async.} =
    info "Adapter read from socket", adapter = self.name, data = self.wrotestr
    let ret = newFuture[StringView]("read MyAdapter")
    self.rv.reset()

    await sleepAsync(2)
    self.rv.write(self.wrotestr)
    
    return self.rv
   
   
type Nimche = ref object of Tunnel
    mark: string

proc new*(t: typedesc[Nimche], name = "unnamed tunenl"): Nimche =
    trace "new Tunnel", name 
    result = Nimche(name: name, hsize: 5)
    result.mark = " " & name & " "


method write*(self: Nimche, data: StringView, chain: Chains = default): Future[void] {.raises: [], gcsafe.} =
    writeChecks(self, data):
        if firstwrite : copyMem(self.writeBuffer.at, addr self.mark[0], self.hsize)
        trace "Appended ", header = (string.fromBytes(makeOpenArray(self.writeBuffer.at, byte, self.hsize))), result = ($data) , name=self.name

    procCall write(Tunnel(self), data)

method read*(self: Nimche, chain: Chains = default): Future[StringView] {.async.}  =
    readChecks(self, await procCall read(Tunnel(self))):
        if firstread : discard
        trace "extracted ", header = string.fromBytes(makeOpenArray(self.readBuffer.at, byte, self.hsize)), result = $self.rv
    return self.rv


    # let ret = newFuture[StringView]("read")
    # var stream = procCall read(Tunnel(self))
    # stream.addCallback proc(u: pointer) =
    #     var data = stream.value()
    #     readChecks(self, data):
    #         if firstread : discard
    #         discard

    #     trace "extracted ", header = string.fromBytes(makeOpenArray(self.readBuffer.at, byte, self.hsize)), result = $data

    #     ret.complete data
    # return ret

suite "Suite for testing basic tunnel":
    setup: discard
        # echo "run before each test"
        # bind iao
    teardown: discard
        # echo "run after each test"


    test "Test basic read write":
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
    test "Test what happens with 0 cap":
        proc run() {.async.} =
            var nc1: Nimche = Nimche.new(name = "nc1")
            var nc2: Nimche = Nimche.new(name = "nc2")
            var nc3: Nimche = Nimche.new(name = "nc3")
            var nc4: Nimche = Nimche.new(name = "nc4")
            nc1.chain(nc2).chain(nc3).chain(nc4).chain(MyAdapter.new())
            
            for i in 0..3:
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

    test "Test what happens with multi write with 0 cap":
        proc run() {.async.} =
            var nc1: Nimche = Nimche.new(name = "nc1")
            var nc2: Nimche = Nimche.new(name = "nc2")
            var nc3: Nimche = Nimche.new(name = "nc3")
            var nc4: Nimche = Nimche.new(name = "nc4")
            nc1.chain(nc2).chain(nc3).chain(nc4).chain(MyAdapter.new())
            
            var write_data = "hallo"
            info "Data to send through tunnels", write_data
            var writeview = newStringView(cap = 0)
            
            for i in 0..3:
                writeview.write(write_data)
                info "View to send through tunnels", writeview
                await nc1.write(writeview)
                let read = $(await nc1.read())
                # print read
                check(read == write_data)
        waitFor run()

    test "Test try to read when not enough data remains":
        proc run() {.async.} =
            var nc1: Nimche = Nimche.new(name = "nc1")
            var nc2: Nimche = Nimche.new(name = "nc2")
            var nc3: Nimche = Nimche.new(name = "nc3")
            var nc4: Nimche = Nimche.new(name = "nc4")
            nc1.chain(nc2).chain(nc3).chain(nc4).chain(MyAdapter.new())
            
            var write_data = "hallo"
            info "Data to send through tunnels", write_data

            var writeview = newStringView(cap = 0)
            writeview.write(write_data)
            info "View to send through tunnels", writeview
            
            await nc4.write(writeview)
            for i in 0..10:
                expect(FlowReadError):
                    let read = $(await nc1.read())

        waitFor run()














