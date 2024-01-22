import std/[strformat, macros, strutils, ospaths]
from macros import hint, error, warning


when fileExists("private.nim"):
    import private

const output_name = "RTCF"
const libs_dir = "libs"
const output_dir = "dist"
const src_dir = "src"
const tests_dir = "tests" #sources located inside src
const utils_dir = "utils" #sources located inside src
const bindings_dir = "generator" #sources located inside src
const bindings_output_dir = "generated" #sources located inside src

const build_cache = hostOS/hostCPU
const nimble_path = libs_dir&"/nimble"

const backend = "c"
const compiler = "gcc" #gcc, switch_gcc, llvm_gcc, clang, bcc, vcc, tcc, env, icl, icc, clang_cl
const gc = "orc" # refc(thread local) | boehm

const threads = false

const enable_chronicles = true

template outFile(dir, name: string): string = dir / name & (when defined(windows): ".exe" else: "")

template require(package: untyped) =
    block:
        when compiles(typeof(package)):
            let str {.inject.}: string = package
            exec &"nimble -l install --nimbleDir:{nimble_path} {str} -y"
        else:
            let ast {.inject.} = astToStr(package)
            exec &"nimble -l install --nimbleDir:{nimble_path} {ast} -y"



task install, "install nim deps":
    require illwill
    require jsony
    require secp256k1
    require malebolgia
    require pretty
    require benchy
    require websock
    require zippy
    require checksums
    require stew
    require results
    require bearssl
    require httputils
    require unittest2
    # require &"""--passL:-L"{getCurrentDir() / libs_dir }/" futhark"""

    #remove chronos since we patched it, use our patch
    for d in listDirs nimble_path/"pkgs2":
        if d.contains("chronos"):
            rmDir d

    # exec """cmd /c "echo | set /p dummyName=Hello World" && exit"""
    # exec """cmd /c "echo | set /p dummyName=Hello World" && exit"""
    hint "Attempt to download submodules"
    exec "git submodule update --recursive"
    hint "Finished prepairing required tools."


template sharedBuildSwitches(){.dirty.} =

        #private.nim:
        #   const auto_domain:string = "your domain"
        #   const auto_certificate:string = "retn pem"
        #   const auto_private_key:string = "pkey pem"

    switch("nimblePath", nimble_path&"/pkgs2")
    # switch("mm", "orc") not for chronos
    switch("mm", gc)
    switch("cc", compiler)
    switch("threads", if threads:"on" else: "off")
    # switch("exceptions", "setjmp")
    switch("warning", "HoleEnumConv:off")
    switch("warning", "BareExcept:off")

    #untill Araq fixes it in devel https://github.com/nim-lang/Nim/pull/23100
    switch("d", "useMalloc")

    switch("d", "asyncBackend:chronos")

    switch("path", src_dir)
    switch("path", src_dir/utils_dir)
    switch("path", libs_dir)
    switch("path", libs_dir&"/chronos/")
    switch("passC", "-I "&libs_dir&"/hwinfo/include/")

    switch("nimcache", "build"/build_cache)

    # switch("multimethods", "on")

    # switch("define", "ssl")
    # switch("passC", "-I "&libs_dir&"/hwinfo/include/")

    switch("d",&"""chronicles_enabled={ (if enable_chronicles: "on" else: "off") }""")
    # switch("experimental", "views")
    switch("d", "textlines=textblocks[stdout]")
    # switch("d", "chronicles_line_numbers")
    switch("d", "chronicles_colors=AnsiColors")
    switch("d", "chronicles_disable_thread_id")
    switch("d", "chronicles_timestamps=none")
    switch("import", src_dir/utils_dir/"helpers.nim")


    when declared(auto_domain):
        switch("d", "autoCert=" & auto_certificate)
        switch("d", "autoPKey=" & auto_private_key)
        switch("d", "autoDomain=" & autoDomain)
        switch("d", "autoApiToken=" & auto_api_token)
        switch("d", "autoZoneID=" & auto_zone_id)
    else:
        warning "Auto Mode is disabled! you need to provide private.nim with your cert+pkey+api values"


    
    switch("d", "chronicles_disabled_topics=websock")

 
    when Release:
        
        switch("d", "chronicles_log_level=INFO")


        switch("opt", "speed")
        switch("debugger", "off")
        switch("d", "release")

        switch("passL", " -s")
        switch("debuginfo", "off")
        switch("passC", "-DNDEBUG")
        switch("passC", "-flto")
        switch("passL", "-flto")

        switch("obj_checks", "off")
        switch("field_checks", "off")
        switch("range_checks", "off")
        switch("bound_checks", "off")
        switch("overflow_checks", "off")
        switch("floatChecks", "off")
        switch("nanChecks", "off")
        switch("infChecks", "off")
        # switch("assertions","off")
        switch("stacktrace", "off")
        switch("linetrace", "off")
        switch("debugger", "off")
        switch("line_dir", "off")
        # switch("passL", " -static")
        # switch("passL", " -static-libgcc")
        # switch("passL", " -static-libstdc++")
    else:
        switch("d", "debug")
        switch("d", "chronicles_log_level=INFO")
        switch("g")
        switch("d","debuginfo")
        switch("debugger", "native")
        switch("lineDir", "on")
        switch("lineTrace", "on")
        switch("opt", "none")
        # if threads:switch("passC", "-fsanitize=thread")
        # if threads:switch("passL", "-fsanitize=thread")

    switch("outdir", output_dir)
    switch("out", output_file)
    switch("backend", backend)

task generate, "generate lz4 bindings":
    const Release = false

    if paramCount() < 2:
        error "pass the test file as a parameter like: nim test test.nim"

    let cmd = paramStr(2)
    let file =
        case cmd:
            of "lz4":
                "lz4.nim"
            else:
                error "generator not found or invalid."; quit(1)

    if not fileExists(src_dir / bindings_dir / file):
        error &"file {src_dir / tests_dir / file} dose not exists";

    let build_cache = "Generators" / file[0 .. file.rfind('.')] / build_cache
    const output_dir = output_dir / bindings_dir
    let output_file = outFile(output_dir, file)

    setCommand("c", src_dir / bindings_dir / file)
    sharedBuildSwitches()
    switch("r", "")
    switch("threads", "off")
    switch("d", "nimUnittestColor=on")
    switch("d", "useFuthark")
    switch("d", "log_hooks:off")
    switch("d", "OUTPUT_DIR:" & currentSourcePath.parentDir() / src_dir / bindings_output_dir)
    switch("d", "ROOT_DIR:" & currentSourcePath.parentDir())


    putEnv("UNITTEST2_OUTPUT_LVL", "COMPACT")



task test, "test a single file":
    const Release = false

    if paramCount() < 2:
        error "pass the test file as a parameter like: nim test test.nim"; return

    let file = paramStr(2)
    if not fileExists(src_dir / tests_dir / file):
        error &"file {src_dir / tests_dir / file} dose not exists"

    let build_cache = "Tests" / file[0 .. file.rfind('.')] / build_cache
    const output_dir = output_dir / tests_dir
    let output_file = outFile(output_dir, file)

    setCommand("c", src_dir / tests_dir / file)
    sharedBuildSwitches()
    switch("r", "")
    switch("d", "nimUnittestColor=on")
    switch("d", "testing")
    switch("d", "log_hooks:off")

    putEnv("UNITTEST2_OUTPUT_LVL", "COMPACT")

task tests, "run all tests":
    for f in listFiles(src_dir / tests_dir):
        if not (f.len > 4 and f[^4..^1] == ".nim"): continue
        let fn = f[f.rfind(DirSep)+1 .. f.high]
        hint "Compile and Test => " & fn[0 .. fn.rfind(".")-1]
        try:
            exec "nim test " & fn
        except:
            warning "Test failed, continue other tests? [Enter]"
            discard readLineFromStdin()

task build_rtcf_release, "builds rtcf release":
    const Release = true
    let build_cache = "Release" / build_cache
    const output_dir = output_dir / "release"
    const output_file = outFile(output_dir, output_name)
    setCommand("c", src_dir&"/main.nim")
    sharedBuildSwitches()

task build_rtcf_debug, "builds rtcf debug":
    const Release = false
    let build_cache = "Debug" / build_cache
    const output_dir = output_dir / "debug"
    const output_file = outFile(output_dir, output_name)
    setCommand("c", src_dir&"/main.nim")
    sharedBuildSwitches()

#only a shortcut
task build, "builds only rtcf (debug)":
    # echo staticExec "taskkill /IM rtcf.exe /F"
    
    var release = false
    if paramCount() >= 2:
        if paramStr(2).toLower == "release":
            release = true
    if release:
        exec "nim build_rtcf_release"
    else:
        exec "nim build_rtcf_debug"

    # echo staticExec "pkill rtcf"
    # echo staticExec "taskkill /IM rtcf.exe /F"
    # withDir(output_dir):`
        # exec "chmod +x rtcf"
        # echo staticExec "./rtcf >> output.log 2>&1"

