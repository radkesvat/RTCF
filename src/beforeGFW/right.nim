import chronos


logScope:
    topic = "Iran RightSide"










proc run*() {.async.}= 
    while true:
        info "hi from right"
        await sleepAsync(1000)

