# a box of stringviews, you take when you need, then put it back
# why tho? because we can elide reallocates = faster runtime = less memory used
import stringview, sequtils

logScope:
    topic = "Store"


const DefaultStoreCap = 500
const DefaultStrvCap = 4096

type Store* = ref object
    available: seq[Stringview]
    maxCap: int

proc new*(t: typedesc[Store], cap = DefaultStoreCap): Store =
    new result
    result.avalable = newSeqOfCap(cap)
    for i in 0 ..< cap:
        result.available[i] = newStringView(cap = DefaultStrvCap)
    result.avalable.setLen(cap)
    result.maxCap = cap
    trace "Initialized", cap = cap, allocated = cap * sizeof(StringView)


template requires(self: Store, count: int) =
    if self.available.len < count:
        trace "Allocating again", wasleft = self.available.len, requested = count, increase_to = self.maxCap

        self.available.setLen(self.maxCap)

        for i in self.available.len ..< self.maxCap:
            self.available[i] = newStringView(cap = DefaultStrvCap)



proc pop*(self: Store): Stringview =
    self.requires 1
    return self.available.pop()

proc reuse*(self: Store, v: sink Stringview) =
    self.available.add(move v)
