import chronos,globals

logScope:
    topic = "Iran LeftSide"














proc run*() {.async.}= 
    while true:
        info "hi from left"
        await sleepAsync(1000)

