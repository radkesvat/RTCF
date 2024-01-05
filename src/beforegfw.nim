import std/[ os, osproc]
import std/exitprocs
import globals, chronos
import system/ansi_c except SIGTERM
from globals import nil
import beforeGFW/[left, right]

logScope:
    topic = "Iran"

var cloudflareIps = @[
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22"
]

when NimMajor >= 2 and hasThreadSupport:
    when defined(posix):
        from posix import pthread_cancel
    else:
        from std/private/threadtypes import terminateThread

    proc exitMultiThread(threads: sink seq[Thread[int]]) =
        when NimMajor >= 2 :
            when defined(posix):
                addExitProc(proc() =
                    for thr in threads:
                        when compiles(pthread_cancel(thr.sys)):
                            discard pthread_cancel(thr.sys)
                        if not isNil(thr.core):
                            when defined(gcDestructors):
                                c_free(thr.core)
                            else:
                                deallocShared(thr.core)
                )
            else:
                addExitProc(proc() =
                    for thr in threads:
                        when compiles(terminateThread(thr.sys, 1'i32)):
                            discard terminateThread(thr.sys, 1'i32)
                        if not isNil(thr.core):
                            when defined(gcDestructors):
                                c_free(thr.core)
                            else:
                                deallocShared(thr.core)
                    )
        else:
            discard



proc resetIptables() =
    info "reseting iptable nat"
    doAssert 0 == execCmdEx("iptables -t nat -F").exitCode
    doAssert 0 == execCmdEx("iptables -t nat -X").exitCode
    doAssert 0 == execCmdEx("ip6tables -t nat -F").exitCode
    doAssert 0 == execCmdEx("ip6tables -t nat -X").exitCode



proc isPortFree(port: Port): bool =
    try:
        var address = initTAddress("::", port)
        var server = createStreamServer(address, proc(server: StreamServer,
                               client: StreamTransport) {.async: (raises: []).} = discard
            , flags = {ServerFlags.ReuseAddr})

        waitFor server.closeWait()
        return true
    except:
        return false


proc ruleCF_singlePort(dport: Port, lport: Port) =
    for ip in cloudflareIps:
        doAssert 0 == execCmdEx(&"""sudo iptables -t nat -A PREROUTING -p tcp -s {ip} --dport {dport} -j REDIRECT --to-port {lport}""").exitCode
        doAssert 0 == execCmdEx(&"""sudo iptables -t nat -A PREROUTING -p tcp -s {ip} --dport {dport} -j REDIRECT --to-port {lport}""").exitCode

proc ruleCF_multiPort(dport_min: Port, dport_max: Port, lport: Port) =
    for ip in cloudflareIps:
        doAssert 0 == execCmdEx(&"""sudo iptables -t nat -A PREROUTING -p tcp -s {ip} --dport {dport_min}:{dport_max} -j REDIRECT --to-port {lport}""").exitCode
        doAssert 0 == execCmdEx(&"""sudo iptables -t nat -A PREROUTING -p tcp -s {ip} --dport {dport_min}:{dport_max} -j REDIRECT --to-port {lport}""").exitCode


proc createIptableMultiportRules(min: Port, max: Port, lport: Port, ruleudp: bool) =
    proc rule(protocal: string) =
        if not (min == 0.Port or max == 0.Port):
            doAssert 0 == execCmdEx(&"""iptables -t nat -A PREROUTING -p {protocal} --dport {min}:{max} -j REDIRECT --to-port {lport}""").exitCode
            doAssert 0 == execCmdEx(&"""ip6tables -t nat -A PREROUTING -p {protocal} --dport {min}:{max} -j REDIRECT --to-port {lport}""").exitCode

        for port in globals.multi_port_additions:
            doAssert 0 == execCmdEx(&"""iptables -t nat -A PREROUTING -p {protocal} --dport {port} -j REDIRECT --to-port {lport}""").exitCode
            doAssert 0 == execCmdEx(&"""ip6tables -t nat -A PREROUTING -p {protocal} --dport {port} -j REDIRECT --to-port {lport}""").exitCode

    rule("tcp")
    if ruleudp: rule("udp")


proc findCFPort(): Port =
    info "Finding internal port"
    when defined(windows):
        var https_ports = [443, 2053, 2083, 2087, 2096, 8443]
        for p in https_ports:
            if globals.listen_port != p.Port and isPortFree(p.Port): return p.Port
        return 0.Port

    else:
        let max = uint16.high
        for p in countdown(max, 0):
            if globals.listen_port != p.Port and isPortFree(p.Port): return p.Port
        return 0.Port   

proc rightThread(threadID: int){.thread.} =
    warn "RightThread spawend"
    var disp = getThreadDispatcher()
    waitFor right.run(threadID)


proc leftThread(threadID: int){.thread.} =
    warn "LeftThread spawend"
    var disp = getThreadDispatcher()
    waitFor left.run(threadID)


proc main() =

    #full reset iptables at exit (if the user allowed)
    if globals.multi_port and globals.reset_iptable:
        addExitProc do(): resetIptables()
        setControlCHook do(){.noconv.}: quit()
        c_signal(SIGTERM, proc(a: cint){.noconv.} = quit())

    #disable ufw
    when defined(linux) and not defined(android):
        if globals.disable_ufw:
            if not isAdmin():
                fatal "Disabling ufw requires root. !"
                info "Please run as root. or start with --keep-ufw "
                quit(1)
            if 0 != execShellCmd("sudo ufw disable"):
                error " < sudo ufw disable > failed. ufw might still be active. Ignoring..."

    if globals.reset_iptable and not defined(windows): resetIptables()

    # find a port for second thread
    var cfl_port = findCFPort();
    if cfl_port == 0.Port:
        fatal "could not find and listen on a random port!"; quit(1)


    if globals.multi_port:
        if not (globals.multi_port_min == 0.Port or globals.multi_port_max == 0.Port):
            ruleCF_multiPort(globals.multi_port_min, globals.multi_port_max, cfl_port)
        for port in globals.multi_port_additions:
            ruleCF_singlePort(port, cfl_port)
        createIptableMultiportRules(globals.multi_port_min, globals.multi_port_max,
        globals.listen_port, globals.accept_udp)
    else:
        when defined(windows):
            notice "In foreign server, set iran-port to this port -> ", port = cfl_port
        else:
            ruleCF_singlePort(globals.listen_port, cfl_port)

    globals.cf_listen_port = cfl_port
    
    proc singlethread() =
        asyncSpawn left.run(1)
        asyncSpawn right.run(1)
        runForever()

    when hasThreadSupport:

        proc mutithread() =
            var threads_left: int = globals.threadsCount.int
            var threads = newSeqOfCap[Thread[int]](cap = 20)
            var i = 0
            while threads_left > 0:
                threads.setLen(threads.len+2)
                # TODO: Set the scheduling policy to SCHED_FIFO (real-time)
                createThread(threads[i], leftThread, i+1);  inc i
                createThread(threads[i], rightThread, i+1); inc i
                threads_left -= 2

            info "Waiting for spawend threads"
            joinThreads(threads)
            warn "All spawend threads have finished"
            exitMultiThread(threads)

        doAssert globals.threadsCount >= 1

        if globals.threadsCount == 1:
            singlethread()
        else:
            mutithread()

    else:
        doAssert globals.threadsCount == 1
        singlethread()



proc start* = main()



