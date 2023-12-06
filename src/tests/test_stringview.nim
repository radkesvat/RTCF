import stringview, pretty, unittest2

logScope:
    topic = "Test"

suite "testing the stringviews type and calculations":
    #setup
    var test_buf1: array[100, char]
    for i, e in mpairs test_buf1:
        e = i.char

    const cap = 200
    var strv = newStringView(cap = cap)

    let dummy = "sbacedaskcs'ckp'k28/9999999914/]2 xu/19]8i2 eoj \\\\\\\\\\\\"


    setup:
        # echo "run before each test"
        strv = newStringView(cap = cap)

        # bind iao
    teardown:
        discard
        # echo "run after each test"
        # strv.reset()

    test "essential truths":
        # give up and stop if this fails
        require(strv.len == 0)
        require(strv.lCap == cap)
        require(strv.rCap == cap)
        require(strv.high == -1)
        require(strv.low == 0)
        require(strv.buf != nil)

    test "Test Hooks":
        strv.write("salam")
        var strv2: StringView = StringView()
        check(strv2 != nil)
        strv2 = strv
        check(strv2.len == strv.len)
        check(strv2.lCap == strv.lCap)
        check(strv2.rCap == strv.rCap)
        check(strv2.high == strv.high)
        check(strv2.low == strv.low)
        check(strv2.buf == strv.buf)
        checkpoint "Tested simple copy"

        # strv2[] = ensureMove(move(strv[]))
        # echo "move"
        # strv2[] = move(strv[])
        `=sink`(strv2[], strv[])
        # `=wasMoved`(strv[])
        # echo strv.repr
        # echo(strv2.buf == strv.buf)
        check((strv[] == zeroDefault(typeof(StringView()[]))))

        checkpoint "Tested sink"

        # strv[] = strv[]

        # strv2[] = strv2[]
        # check(strv[] == zeroDefault(typeof(StringView()[])))
        # check((strv2[] == strv2[]))
        # checkpoint "Tested selfassign"

    test "Test destroy reset state begin":
        strv.setLen(10)
        check(strv.len == 10)
    test "Test destroy reset state begin":
        check(strv.len == 0)

    test "Test streaming 1":
        var old_buf = strv.buf
        copyMem(strv.buf, addr test_buf1[0], test_buf1.len)
        strv.setLen(test_buf1.len)

        check(strv.len == test_buf1.len)
        # check(strv.leftCap == cap - test_buf1.len)

        check(strv.rCap == cap)
        check(strv.lCap == cap)

        check(strv.low == 0)
        check(strv.high == test_buf1.len-1)
        check(strv.buf == old_buf)

    test "Test streaming 2":
        #shifting x bytes
        for x in 0 .. test_buf1.len:
            checkpoint("check point x = " & $x)
            var old_buf = strv.buf


            copyMem(strv.buf, addr test_buf1[0], test_buf1.len)
            strv.setLen(test_buf1.len)
            strv.shiftr x


            check(strv.len == test_buf1.len - x)
            check(strv.rCap == cap - x)
            check(strv.low == 0)
            check(strv.high == test_buf1.len - (x+1))

            # print (old_buf) ," , ", (old_buf.offset x)
            check(strv.buf == (old_buf.offset x))

            strv.reset()

    test "Test streaming 3 (failures)":
        #shifting x bytes
        for x in test_buf1.len+1 .. test_buf1.len * 2:
            expect(AssertionDefect):
                checkpoint("Defect check point x = " & $x)
                var old_buf = strv.buf

                copyMem(strv.buf, addr test_buf1[0], test_buf1.len)
                strv.setLen(test_buf1.len)
                strv.shiftr x

                check(strv.len == test_buf1.len - x)
                check(strv.rCap == cap - test_buf1.len)
                check(strv.low == 0)
                check(strv.high == test_buf1.len-1)
                check(strv.buf == (old_buf.offset x))

            strv.reset()

    test "Test streaming 4 (failures)":
        strv.setLen cap



        strv = newStringView(cap = 0)
        expect(AssertionDefect):
            strv.shiftr 1
        strv = newStringView(cap = 11)
        expect(AssertionDefect):
            strv.shiftr 12
        expect(AssertionDefect):
            strv = newStringView(cap = -1)

        strv = newStringView(cap = cap)

        strv.reset()

    test "Test streaming 5":
        strv = newStringView(cap = cap)
        require(strv.rCap == 200)
        require(strv.len == 0)
        require(strv.low == 0)

        strv.setLen 200+1
        check(strv.len == 200+1)
        check(strv.rCap == 256)
        check(strv.low == 0)
        check(strv.high == 200)
    test "Test streaming 6":
        strv.write(dummy)
        check(cmpMem(strv.buf, addr (dummy[0]), len(dummy)) == 0)

        for x in 0..(dummy.high):
            checkpoint("check point x = " & $x)
            check(cmpMem(strv.buf, addr (dummy[x]), len(dummy)-x) == 0)
            strv.shiftr 1

    test "Test streaming 7":
        strv = newStringView(cap = 0)

        strv.setLen(dummy.len)
        var buf = strv.buf
        copyMem(buf, addr dummy[0], dummy.len)
        for x in 0..(dummy.high):
            checkpoint("check point x = " & $x)
            check(cmpMem(strv.buf, addr (dummy[x]), len(dummy)-x) == 0)
            strv.shiftr 1

    test "Test string creation":
        strv.setLen(dummy.len)
        var buf = strv.buf
        copyMem(buf, addr dummy[0], dummy.len)
        check(dummy == $strv)
        for x in 0..(dummy.high):
            check(dummy[x .. dummy.high] == $strv)
            strv.shiftr 1
        strv.reset()
        strv.write(dummy)
        check(dummy == $strv)
        for x in 0..(dummy.high):
            check(dummy[x .. dummy.high] == $strv)
            strv.shiftr 1

    test "Test string creation2":
        strv.write("salam")
        echo strv


    test "views":
        strv.write("000000000")

        var v1 = strv.view(3)
        var v2 = strv.view(3)
        var v3 = strv.view(3)
        strv.write("123456789")

        # check(v1 == ['1','2','3'])
        # check(v2 == ['4','5','6'])
        # check(v3 == ['7','8','9'])

        var vc1{.cursor.} = v1



    test "test views and shifts simple 1":
        strv = newStringView(cap = 0)
        for i in 0..test_buf1.high:
            strv.write(test_buf1)
            strv.shiftr(test_buf1.len())
            check(strv.len == 0)
            check(strv.high == -1)


    test "test views and shifts simple 2":
        strv = newStringView(cap = 0)
        for i in 0..test_buf1.high:
            strv.write(test_buf1)
            strv.shiftr(test_buf1.len())
            strv.shiftl(test_buf1.len())
            check(strv.len == 100)
            check(strv.high == 99)
            strv.reset()

    test "test views and shifts simple 3":
        strv = newStringView(cap = 0)
        var lcap = 0
        var rcap = 0
        for i in 0..test_buf1.len():
            strv.shiftl(test_buf1.len())
            if rcap == 0:
                rcap = strv.rCap
                lcap = strv.lCap

            strv.write(test_buf1)
            check(strv.rCap == rcap)
            check(strv.lCap == lcap)
            strv.reset()
            checkpoint("checkpoint i = " & $i)


    test "test views and shifts simple 4":
        strv = newStringView(cap = 0)
        strv.shiftl(2000)
        strv.shiftr(2000)
        var rcap = strv.rCap
        var lcap = strv.lCap
        for i in 0..200:
            strv.reset()
            strv.shiftl(2000)
            strv.shiftr(2000)
            expect(AssertionDefect):
                strv.shiftr(1)

            check(strv.rCap == rcap)
            check(strv.lCap == lcap)
            check(strv.len == 0)
            check(strv.lCap == lcap)
            checkpoint("checkpoint i = " & $i)

    test "test views and shifts simple 5":
        strv = newStringView(cap = 0)
        strv.shiftl(2000)
        strv.write "salam"
        for i in 0.."salam".high:
            strv.shiftr(1)

        expect AssertionDefect:
            strv.shiftr(1)

    test "test views and shifts simple 6":
        strv = newStringView(cap = 0)
        strv.shiftl(2000)
        strv.write "salam"
        for i in 0.."salam".high:
            strv.shiftr(1)

        expect AssertionDefect:
            strv.shiftr(1)

    test "test views and shifts simple 7":
        strv = newStringView(cap = 0)
        strv.shiftl(2000)
        strv.write "salam"
        for i in 0.."salam".high:
            strv.shiftr(1)

        expect AssertionDefect:
            strv.shiftr(1)

    test "test views and shifts complex":
        strv = newStringView(cap = 0)
        strv.shiftl 1
        strv.write "abc"

        let v1 = strv.view(1)
        strv.shiftr 1

        let v2 = strv.view(1)
        strv.shiftr 1

        let v3 = strv.view(1)

        expect AssertionDefect:
            discard strv.view(2)

        proc must() =
            check(v1.at[0] == 'a')
            check(v2.at[0] == 'b')
            check(v3.at[0] == 'c')
        must()
        for i in 0..500: strv.shiftl 1; must()
        for i in 0..500: strv.shiftr 1; must()
        strv.reserve(200)
        for i in 0..200: strv.shiftl 1; must()
        for i in 0..400: strv.shiftr 1; must()



    test "stremaing and shifts 1":
        strv = newStringView(cap = 0)
        for i in 0 .. 100:
            strv.write $(i.chr)
            strv.shiftr 1

        for i in countdown(100, 0):
            strv.shiftl 1
            check($strv == $(i.char))
            strv.consume 1
            checkpoint("check point i = " & $i)

    test "stremaing and shifts 2":
        strv = newStringView(cap = 0)
        const phrase = "564aeku7k 123654 salam also WTFD?"
        for i in 0 .. 100:
            strv.write phrase
            strv.shiftr phrase.len

        for i in countdown(100, 0):
            strv.shiftl phrase.len
            check($strv == phrase)
            strv.consume phrase.len
            checkpoint("check point i = " & $i)



    suiteTeardown:
        echo "End Suite"

