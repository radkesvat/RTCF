import std/[cpuinfo, locks, strutils, os]
import chronos/unittest2/asynctests
import chronos/threadsync
import std/exitprocs
import system / ansi_c
import globals
import system/ansi_c except SIGTERM


#returns logical cores which each ``can`` run a thread
let numProcs = countProcessors() - 1


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
    echo "reseting iptable nat"
    assert 0 == execCmdEx("iptables -t nat -F").exitCode
    assert 0 == execCmdEx("iptables -t nat -X").exitCode
    if ip6tablesInstalled():
        assert 0 == execCmdEx("ip6tables -t nat -F").exitCode
        assert 0 == execCmdEx("ip6tables -t nat -X").exitCode



proc main()=
    #full reset iptables at exit (if the user allowed)
    if globals.multi_port and globals.reset_iptable :
        addExitProc do(): globals.resetIptables()
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

