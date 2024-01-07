import chronos, chronos/timer, threading/channels



var s = newSeqOfCap[int64](cap = 100000)
s.setLen 100000
for i in 0..<100000:
    s[i] = Moment.now().epochNanoSeconds()

for i in 0..<100000:
    for x in i+1..<100000:
        if s[i] == s[x]:
            echo "FOUND ",$s[i]," == ",$s[x]
echo "end"