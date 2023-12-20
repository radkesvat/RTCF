import tunnel, pretty, unittest2, strutils
import stew/byteutils

logScope:
    topic = "Test"
{.push raises: [].}

const rq_tag: InfoTag = InfoTag(0x123)


type MyAdapter* = ref object of Adapter
    wrotestr: string
    receivedsig: Signals

method init(self: MyAdapter, name: string){.base, raises: [], gcsafe.} =
    procCall init(Adapter(self), name, hsize = 5)
    self.readLine = newStringView(cap = 2000)
    self.receivedsig = invalid

proc new*(t: typedesc[MyAdapter]): MyAdapter =
    trace "new MyAdapter"
    result = MyAdapter()
    result.init(name = "MyAdapter")


method write*(self: MyAdapter, rp: StringView, chain: Chains = default): Future[void] {.async.} =
    info "Adapter write to socket", adapter = self.name, data = $rp
    self.writeLine = rp
    #wrote to socket
    await sleepAsync(2)
    self.wrotestr = $self.writeLine

    self.writeLine.restart()



method read*(self: MyAdapter, chain: Chains = default): Future[StringView] {.async.} =
    info "Adapter read from socket", adapter = self.name, data = self.wrotestr
    self.readLine.restart()

    await sleepAsync(2)
    self.readLine.write(self.wrotestr)

    return self.readLine


method signal*(self: MyAdapter, dir: SigDirection, sig: Signals, chain: Chains = default) =
    info "Adapter received signal", sig = sig
    self.receivedsig = sig



type Nimche = ref object of Tunnel
    mark: string

method init(self: Nimche, name: string){.base, raises: [], gcsafe.} =
    procCall init(Tunnel(self), name, hsize = 5)
    self.mark = " " & name & " "

proc new*(t: typedesc[Nimche], name: string): Nimche =
    trace "new Tunnel", name
    result = Nimche()
    result.init(name = name)


method write*(self: Nimche, data:  StringView, chain: Chains = default): Future[void] {.raises: [], gcsafe.} =
    setWriteHeader(self, data):
        copyMem(self.getWriteHeader, addr self.mark[0], self.hsize)
        trace "Appended ", header = (string.fromBytes(makeOpenArray(self.getWriteHeader, byte, self.hsize))), to = ($self.writeLine), name = self.name

    procCall write(Tunnel(self), self.writeLine)

method read*(self: Nimche, chain: Chains = default): Future[StringView] {.async.} =
    setReadHeader(self, await procCall read(Tunnel(self)))
    trace "extracted ", header = string.fromBytes(makeOpenArray(self.getReadHeader, byte, self.hsize)), result = $self.readLine
    return self.readLine


method signal*(self: Nimche, dir: SigDirection, sig: Signals, chain: Chains = default) =
    info "Forwarding signal", name = self.name, sig = sig
    #if you want do something, then forward to others
    procCall signal(Tunnel(self), dir, sig, chain)

method requestInfo*(self: Nimche, target: Hash, dir: SigDirection, tag: InfoTag, chain: Chains = default): ref InfoBox {.gcsafe.} =
    if isMe(self,target):echo "was me"
    if isMe(self,target) and tag == rq_tag:
        info "Handling requestInfo", name = self.name, target = target, tag = tag

        var info = new InfoBox
        var sample{.global.}: uint16 = 0xffff
        info[] = (tag, 2, cast[pointer](addr sample))
        info
    else:
        info "Passing requestInfo", name = self.name, target = target, tag = tag

        procCall requestInfo(Tunnel(self), target, dir, tag, chain)


    # let ret = newFuture[StringView]("read")
    # var stream = procCall read(Tunnel(self))
    # stream.addCallback proc(u: pointer) =
    #     var data = stream.value()
    #     readChecks(self, data):
    #         if firstread : discard
    #         discard

    #     trace "extracted ", header = string.fromBytes(makeOpenArray(self.getWriteHeader, byte, self.hsize)), result = $data

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
                echo "test"
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

    test "Test basic signal":
        proc run() {.async.} =
            var nc1: Nimche = Nimche.new(name = "nc1")
            var nc2: Nimche = Nimche.new(name = "nc2")
            var nc3: Nimche = Nimche.new(name = "nc3")
            var nc4: Nimche = Nimche.new(name = "nc4")
            var adapter = MyAdapter.new()
            nc1.chain(nc2).chain(nc3).chain(nc4).chain(adapter)

            nc1.signal(right, close)
            check(adapter.receivedsig == close)


        waitFor run()

    test "Test basic requestinfo":
        proc run() {.async.} =
            var nc1: Nimche = Nimche.new(name = "nc1")
            var nc2: Nimche = Nimche.new(name = "nc2")
            var nc3: Nimche = Nimche.new(name = "nc3")
            var nc4: Nimche = Nimche.new(name = "nc4")
            var adapter = MyAdapter.new()
            nc1.chain(nc2).chain(nc3).chain(nc4).chain(adapter)


            for i in 0..3:
                let v1: ref InfoBox = nc1.requestInfo("nc3", right, rq_tag)
                check(v1.size == 2)
                check(cast[ptr uint16](v1.value)[] == 0xffff)
            for i in 0..3:
                let v1: ref InfoBox = adapter.requestInfo("nc3", left, rq_tag)
                check(v1.size == 2)
                check(cast[ptr uint16](v1.value)[] == 0xffff)
            for i in 0..3:
                let v1: ref InfoBox = nc1.requestInfo("nc3", both, rq_tag)
                check(v1.size == 2)
                check(cast[ptr uint16](v1.value)[] == 0xffff)
            for i in 0..3:
                let v1: ref InfoBox = adapter.requestInfo("nc3", both, rq_tag)
                check(v1.size == 2)
                check(cast[ptr uint16](v1.value)[] == 0xffff)
            for i in 0..3:
                var v1: ref InfoBox
                v1 = adapter.requestInfo("nc31", both, rq_tag); check(v1 == nil)
                v1 = nc1.requestInfo("nc31", both, rq_tag); check(v1 == nil)
                v1 = nc4.requestInfo("nc31", both, rq_tag); check(v1 == nil)
                v1 = nc3.requestInfo("nc31", both, rq_tag); check(v1 == nil)

                v1 = adapter.requestInfo("nc31", both, InfoTag(0x1223)); check(v1 == nil)
                v1 = nc1.requestInfo("nc31", both, InfoTag(0x123e)); check(v1 == nil)
                v1 = nc4.requestInfo("nc31", both, InfoTag(0x123a)); check(v1 == nil)
                v1 = nc3.requestInfo("nc31", both, InfoTag(0x1234)); check(v1 == nil)

                v1 = adapter.requestInfo("nc3", right, rq_tag); check(v1 == nil)
                v1 = nc1.requestInfo("nc3", left, rq_tag); check(v1 == nil)
                v1 = nc4.requestInfo("nc3", right, rq_tag); check(v1 == nil)

                v1 = nc3.requestInfo("nc1", both, rq_tag); check(v1 != nil)
                v1 = nc3.requestInfo("nc4", both, rq_tag); check(v1 != nil)
                v1 = nc3.requestInfo("nc5", both, rq_tag); check(v1 == nil)



            # for i in 0..3:
            #     let v1:ref InfoBox = nc3.requestInfo("nc3",both, rq_tag)
            #     check(v1.size == 2)
            #     check(cast[ptr uint16](v1.value)[] == 0xffff)
        waitFor run()










