import std/[cpuinfo, locks, strutils, os,osproc]
import chronos/unittest2/asynctests
import chronos/threadsync
import std/exitprocs
import system / ansi_c
import globals
import system/ansi_c except SIGTERM
from globals import nil

#returns logical cores which each ``can`` run a thread
let numProcs = cpuinfo.countProcessors() - 1


proc run(arg: int) {.thread.} =
    proc echoundwait(){.async.} =
        while true:
            echo "Hi form " & $arg & "."
            await sleepAsync(1.seconds)
    discard echoundwait()
    waitFor(sleepAsync(2000))

var threads = newSeq[Thread[int]](numProcs)
for i in 0 ..< numProcs:
    createThread(threads[i], run, i+1)
    sleep(12)


joinThreads(threads)

proc resetIptables() =
    info "reseting iptable nat"
    doAssert 0 == execCmdEx("iptables -t nat -F").exitCode
    doAssert 0 == execCmdEx("iptables -t nat -X").exitCode
    doAssert 0 == execCmdEx("ip6tables -t nat -F").exitCode
    doAssert 0 == execCmdEx("ip6tables -t nat -X").exitCode


proc isPortFree(port: Port): bool =
    execCmdEx(&"""lsof -i:{port}""").output.len < 3



proc createIptableMultiportRules() =
    if globals.reset_iptable: resetIptables()
    
    proc rule(protocal : string)=
        if not (globals.multi_port_min == 0.Port or globals.multi_port_max == 0.Port):
            doAssert 0 == execCmdEx(&"""iptables -t nat -A PREROUTING -p {protocal} --dport {globals.multi_port_min}:{globals.multi_port_max} -j REDIRECT --to-port {globals.listen_port}""").exitCode
            doAssert 0 == execCmdEx(&"""ip6tables -t nat -A PREROUTING -p {protocal} --dport {globals.multi_port_min}:{globals.multi_port_max} -j REDIRECT --to-port {globals.listen_port}""").exitCode

        for port in globals.multi_port_additions:
            doAssert 0 == execCmdEx(&"""iptables -t nat -A PREROUTING -p {protocal} --dport {port} -j REDIRECT --to-port {globals.listen_port}""").exitCode
            doAssert 0 == execCmdEx(&"""ip6tables -t nat -A PREROUTING -p {protocal} --dport {port} -j REDIRECT --to-port {globals.listen_port}""").exitCode
    
    rule("tcp")
    if globals.accept_udp: rule("udp")





proc main()=
    #full reset iptables at exit (if the user allowed)
    if globals.multi_port and globals.reset_iptable :
        addExitProc do(): resetIptables()
        setControlCHook do(){.noconv.}: quit()
        c_signal(SIGTERM, proc(a: cint){.noconv.} = quit())

    when defined(linux) and not defined(android):
        if globals.disable_ufw:
            if not isAdmin():
                fatal "Disabling ufw requires root. !"
                info "Please run as root. or start with --keep-ufw "
                quit(1)
            if 0 != execShellCmd("sudo ufw disable"):
                error " < sudo ufw disable > failed. ufw might still be active. Ignoring..."

proc start* = main()

when NimMajor >= 2:
    when defined(posix):
        from posix import pthread_cancel
        
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
        from std/private/threadtypes import terminateThread
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

