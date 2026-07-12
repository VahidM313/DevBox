param(
    [ValidateSet(1, 'Runtimes', 2, 'All')]
    [string]$Stage        = 'All',
    [switch]$Update       = $false,
    [switch]$Clean        = $false,
    [switch]$Reconfigure  = $false,
    [switch]$Full         = $false   # also build clang-tools-extra in Stage 1
)

$ErrorActionPreference = "Stop"

$Repo = "https://github.com/llvm/llvm-project.git"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

$Source      = Join-Path $Root "llvm-project"
$BuildRoot   = Join-Path $Root "build"
$InstallRoot = Join-Path $Root "install"

# Stage 1: throwaway bootstrap compiler (clang + lld only), built with the
# system MinGW gcc/g++. No runtimes are built here anymore -- see "Runtimes"
# below. This keeps Stage 1 fast and avoids ever needing libc++ headers
# before libc++ itself exists.
$Build1   = Join-Path $BuildRoot   "mingw-stage1"
$Install1 = Join-Path $InstallRoot "mingw-stage1"

# Runtimes: libunwind/libcxx/libcxxabi/compiler-rt, built with the Stage 1
# clang+lld (NOT gcc). Installed straight into $Final, i.e. the same prefix
# Stage 2 will install into, so the finished toolchain is self-contained and
# finds its own libc++/compiler-rt/libunwind via normal relative-path
# lookup, with zero extra flags needed at end-use time.
$BuildRuntimes = Join-Path $BuildRoot "mingw-runtimes"

# Stage 2: final, self-hosted toolchain (clang, lld, clang-tools-extra),
# compiled by the Stage 1 clang+lld, linked against the runtimes built
# above instead of being rebuilt from scratch here.
$Build2 = Join-Path $BuildRoot "mingw-stage2"
# $Final  = Join-Path $InstallRoot "mingw"
$Final  = "C:\llvm"

$env:CMAKE_COLOR_DIAGNOSTICS = "ON"
$env:NINJA_STATUS = "[%f/%t | %p | %r running | %w elapsed] "

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Require-Tool($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "$name not found."
    }
}

function Run($cmd) {
    Write-Host ">" $cmd
    Invoke-Expression $cmd
    if ($LASTEXITCODE) {
        throw "$cmd failed"
    }
}

function Remove-IfExists($path) {
    if (Test-Path $path) {
        Write-Host "Removing $path"
        Remove-Item $path -Recurse -Force
    }
}

Require-Tool git
Require-Tool cmake
Require-Tool ninja
Require-Tool gcc
Require-Tool g++

$LinkJobs = [Math]::Max(1, [Math]::Ceiling([Environment]::ProcessorCount / 8))
$Jobs     = [Environment]::ProcessorCount

$sccache = @()
if (Get-Command sccache -ErrorAction SilentlyContinue) {
    Write-Host "sccache enabled"
    $sccache += "-DCMAKE_C_COMPILER_LAUNCHER=sccache"
    $sccache += "-DCMAKE_CXX_COMPILER_LAUNCHER=sccache"
}

# ---------------------------------------------------------------------------
# Repo checkout / update (shared by all stages)
# ---------------------------------------------------------------------------

if (!(Test-Path "$Source\.git")) {
    git clone --depth=1 $Repo $Source
    if ($LASTEXITCODE) { throw "git clone failed" }
}

if ($Update) {
    Push-Location $Source
    git pull --rebase
    if ($LASTEXITCODE) { Pop-Location; throw "git pull failed" }
    Pop-Location
}
else {
    Write-Host "Repository update skipped."
}

Push-Location $Source
$Commit = git rev-parse HEAD
Pop-Location

# ---------------------------------------------------------------------------
# Shared CMake args
# ---------------------------------------------------------------------------

# Common args for the two "llvm" project builds (Stage 1 and Stage 2).
# Runtimes are no longer configured here at all -- they get their own
# standalone build below via llvm-project/runtimes.
function Get-CommonLLVMCMakeArgs($BuildDir, $InstallDir, $Projects) {
    return @(
        "-G", "Ninja",
        "-S", "$Source\llvm",
        "-B", $BuildDir,
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_INSTALL_PREFIX=$InstallDir",
        "-DLLVM_ENABLE_PROJECTS=$Projects",

        "-DLLVM_TARGETS_TO_BUILD=X86",
        "-DLLVM_ENABLE_ASSERTIONS=OFF",
        "-DLLVM_ENABLE_LLD=ON",

        "-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF",

        "-DLLVM_INSTALL_UTILS=ON",
        "-DLLVM_BUILD_TOOLS=ON",
        "-DLLVM_INCLUDE_TESTS=OFF",
        "-DLLVM_INCLUDE_EXAMPLES=OFF",
        "-DLLVM_INCLUDE_BENCHMARKS=OFF",
        "-DLLVM_ENABLE_DOXYGEN=OFF",
        "-DLLVM_ENABLE_SPHINX=OFF",
        "-DLLVM_BUILD_DOCS=OFF",
        "-DLLVM_BUILD_EXAMPLES=OFF",
        "-DLLVM_BUILD_BENCHMARKS=OFF",

        "-DCMAKE_C_FLAGS_RELEASE=-O3",
        "-DCMAKE_CXX_FLAGS_RELEASE=-O3",
        "-DLLVM_PARALLEL_LINK_JOBS=$LinkJobs"
    ) + $sccache
}

# Args for the standalone runtimes build (llvm-project/runtimes), compiled
# with the Stage 1 clang+lld instead of gcc.
function Get-RuntimesCMakeArgs($BuildDir, $InstallDir, $Runtimes, $ClangExe, $ClangxxExe) {

   $Triple = "x86_64-w64-windows-gnu"
   
    return @(
        "-G", "Ninja",
        "-S", "$Source\runtimes",
        "-B", $BuildDir,
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_INSTALL_PREFIX=$InstallDir",
        "-DLLVM_ENABLE_RUNTIMES=$Runtimes",

        "-DCMAKE_C_COMPILER=$ClangExe",
        "-DCMAKE_CXX_COMPILER=$ClangxxExe",
        "-DCMAKE_C_COMPILER_TARGET=$Triple",
        "-DCMAKE_CXX_COMPILER_TARGET=$Triple",
        "-DCMAKE_ASM_COMPILER_TARGET=$Triple",

        "-DLLVM_TARGETS_TO_BUILD=X86",
        "-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF",
        "-DLIBUNWIND_ENABLE_SHARED=OFF",
        "-DLIBUNWIND_INSTALL_STATIC_LIBRARY=ON",


        # Only build compiler-rt builtins -- libFuzzer/sanitizers/XRay/memprof
        # are C++ components that aren't well supported on the mingw target
        # and aren't needed for a compiler toolchain.
        "-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON",
        "-DCOMPILER_RT_BUILD_BUILTINS=ON",
        "-DCOMPILER_RT_BUILD_CRT=OFF",
        "-DCOMPILER_RT_BUILD_SANITIZERS=OFF",
        "-DCOMPILER_RT_BUILD_XRAY=OFF",
        "-DCOMPILER_RT_BUILD_LIBFUZZER=OFF",
        "-DCOMPILER_RT_BUILD_PROFILE=OFF",
        "-DCOMPILER_RT_BUILD_MEMPROF=OFF",
        "-DCOMPILER_RT_BUILD_ORC=OFF",
        "-DCOMPILER_RT_BUILD_GWP_ASAN=OFF",
        "-DCOMPILER_RT_INSTALL_BUILTINS=ON",

        # --- pthread fix -----------------------------------------------
        # By default libc++/libc++abi use the pthreads-via-winpthread shim
        # on mingw targets, which is what produced the "undefined reference
        # to pthread_*" / duplicate winpthread link errors. Telling them to
        # use the native Win32 threading API instead removes the winpthread
        # dependency entirely, so Stage 2 no longer needs -lwinpthread.
        # (Verify these cache variables still exist for your LLVM checkout;
        # they've been stable for a long time but names can drift.)
        "-DLIBCXX_HAS_WIN32_THREAD_API=ON",
        "-DLIBCXXABI_HAS_WIN32_THREAD_API=ON",
        "-DLIBCXXABI_USE_LLVM_UNWINDER=ON",
        # -----------------------------------------------------------------

        "-DLIBCXX_ENABLE_SHARED=OFF",
        "-DLIBCXXABI_ENABLE_SHARED=OFF",
        "-DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON",
        "-DLIBCXX_ENABLE_FILESYSTEM=ON",
        "-DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=ON",
        "-DLIBCXX_INSTALL_HEADERS=ON",
        "-DLIBCXX_ENABLE_STD_MODULES=ON",
        "-DLIBCXX_INSTALL_MODULES=ON",

        "-DCMAKE_C_FLAGS_RELEASE=-O3",
        "-DCMAKE_CXX_FLAGS_RELEASE=-O3",
        "-DLLVM_PARALLEL_LINK_JOBS=$LinkJobs"
    ) + $sccache
}

# Generic configure/build/install runner shared by every stage.
# $WipeInstallOnClean controls whether -Clean also deletes $InstallDir --
# it's $false for Runtimes/Stage 2 since they share the $Final install
# prefix and blowing it away would also delete another stage's output.
# 
function Install-CompilerRtBuiltins($ClangExeForResourceDir) {
    $Triple = "x86_64-w64-windows-gnu"
    $ResourceDir = (& $ClangExeForResourceDir -print-resource-dir).Trim()
    $DestDir = Join-Path $ResourceDir "lib\$Triple"
    $Src = Join-Path $Final "lib\windows\libclang_rt.builtins-x86_64.a"

    if (!(Test-Path $Src)) {
        throw "compiler-rt builtins not found at $Src. Run the Runtimes stage first."
    }

    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    Copy-Item $Src (Join-Path $DestDir "libclang_rt.builtins.a") -Force
    Write-Host "Placed compiler-rt builtins -> $DestDir\libclang_rt.builtins.a"
}

function Invoke-Build($Name, $BuildDir, $InstallDir, [string[]]$CMakeArgs, [bool]$WipeInstallOnClean) {

    if ($Clean) {
        Remove-IfExists $BuildDir
        if ($WipeInstallOnClean) {
            Remove-IfExists $InstallDir
        }
    }

    if ($Reconfigure) {
        Remove-Item "$BuildDir/CMakeCache.txt" -Force -ErrorAction Ignore
        Remove-Item "$BuildDir/CMakeFiles" -Recurse -Force -ErrorAction Ignore
    }

    Write-Host ""
    Write-Host "================================"
    Write-Host " $Name configure"
    Write-Host "================================"

    cmake @CMakeArgs
    if ($LASTEXITCODE) { throw "$Name CMake configuration failed" }

    Write-Host ""
    Write-Host "================================"
    Write-Host " $Name build"
    Write-Host "================================"

    cmake --build $BuildDir --target install --parallel $Jobs -- -d stats
    if ($LASTEXITCODE) { throw "$Name build failed" }

    $Commit | Set-Content "$BuildDir\.llvm_commit"

    Write-Host ""
    Write-Host "$Name installed -> $InstallDir"
}

# ---------------------------------------------------------------------------
# Stage 1: bootstrap compiler (clang + lld only), built with MinGW gcc/g++
# ---------------------------------------------------------------------------

function Run-Stage1 {

    $env:PATH = "C:\mingw64\bin;$env:PATH"
    $env:CC   = "gcc"
    $env:CXX  = "g++"

    $Projects = if ($Full) { "clang;clang-tools-extra;lld" } else { "clang;lld" }

    # Static-link the bootstrap compiler itself so it has no external DLL
    # dependencies while we use it for the Runtimes and Stage 2 builds.
    # This is built with gcc/libstdc++, so winpthread is still needed here.
    $flags = "-static -static-libgcc -static-libstdc++ -Wl,-Bstatic -lwinpthread -Wl,-Bdynamic"

    $extra = @(
        "-DCMAKE_EXE_LINKER_FLAGS=$flags",
        "-DCMAKE_SHARED_LINKER_FLAGS=$flags"
    )

    $cmakeArgs = (Get-CommonLLVMCMakeArgs $Build1 $Install1 $Projects) + $extra
    Invoke-Build "Stage 1 (bootstrap)" $Build1 $Install1 $cmakeArgs $true
}

# ---------------------------------------------------------------------------
# Runtimes: libunwind/libcxx/libcxxabi/compiler-rt, built with the Stage 1
# clang+lld and installed into $Final (the eventual Stage 2 prefix).
# ---------------------------------------------------------------------------

function Run-Runtimes {

    $ClangExe   = Join-Path $Install1 "bin\clang.exe"
    $ClangxxExe = Join-Path $Install1 "bin\clang++.exe"

    if (!(Test-Path $ClangExe)) {
        throw "Stage 1 clang not found at $ClangExe. Run Stage 1 first (-Stage 1 or -Stage All)."
    }

    $env:PATH = "$Install1\bin;C:\mingw64\bin;$env:PATH"
    $env:CC   = $ClangExe
    $env:CXX  = $ClangxxExe

    $Runtimes = "libunwind;libcxx;libcxxabi;compiler-rt"

    $cmakeArgs = Get-RuntimesCMakeArgs $BuildRuntimes $Final $Runtimes $ClangExe $ClangxxExe

    # Use the Stage 1 llvm-ar/llvm-ranlib if available, for consistency
    # with the compiler doing the building.
    $LlvmAr      = Join-Path $Install1 "bin\llvm-ar.exe"
    $LlvmRanlib  = Join-Path $Install1 "bin\llvm-ranlib.exe"
    if (Test-Path $LlvmAr)     { $cmakeArgs += "-DCMAKE_AR=$LlvmAr" }
    if (Test-Path $LlvmRanlib) { $cmakeArgs += "-DCMAKE_RANLIB=$LlvmRanlib" }

    # Don't wipe $Final on -Clean: it's shared with Stage 2's output.
    Invoke-Build "Runtimes" $BuildRuntimes $Final $cmakeArgs $false
}

# ---------------------------------------------------------------------------
# Stage 2: final toolchain (clang, lld, clang-tools-extra), compiled by the
# Stage 1 clang+lld, linked against the runtimes built above.
# ---------------------------------------------------------------------------

function Write-ClangConfig {
    $ResourceDir = ((& (Join-Path $Final "bin\clang.exe") -print-resource-dir).Trim()) -replace '\\','/'
    $Inc  = (Join-Path $Final "include\c++\v1") -replace '\\','/'
    $Lib  = (Join-Path $Final "lib")            -replace '\\','/'
    $LibW = (Join-Path $Final "lib\windows")    -replace '\\','/'

    $cfg = @(
        "-stdlib=libc++",
        "-unwindlib=libunwind",
        "--rtlib=compiler-rt",
        "-fuse-ld=lld",
        "-resource-dir=$ResourceDir",
        "-I$Inc",
        "-L$Lib",
        "-L$LibW",
        "-B$Lib",
        "-B$LibW"
    ) -join "`n"

    Set-Content (Join-Path $Final "bin\clang.cfg")   $cfg
    Set-Content (Join-Path $Final "bin\clang++.cfg") $cfg
}

function Run-Stage2 {

    $ClangExe   = Join-Path $Install1 "bin\clang.exe"
    $ClangxxExe = Join-Path $Install1 "bin\clang++.exe"

    if (!(Test-Path $ClangExe)) {
        throw "Stage 1 clang not found at $ClangExe. Run Stage 1 first (-Stage 1 or -Stage All)."
    }

    $LibcxxMarker = Join-Path $Final "include\c++\v1\vector"
    if (!(Test-Path $LibcxxMarker)) {
        throw "Runtimes not found under $Final. Run the Runtimes stage first (-Stage Runtimes or -Stage All)."
    }

    Install-CompilerRtBuiltins $ClangExe

    $RuntimeLibs    = Join-Path $Final "lib"
    $RuntimeLibsWin = Join-Path $Final "lib\windows"   # compiler-rt builtins live here

    if (!(Test-Path (Join-Path $RuntimeLibsWin "libclang_rt.builtins-x86_64.a"))) {
        throw "compiler-rt builtins not found under $RuntimeLibsWin. Did the Runtimes stage build compiler-rt?"
    }

    # Stage 1's OWN resource dir -- gives us the compiler's builtin
    # intrinsic headers (stddef.h etc). $Final has no lib\clang\<ver>
    # folder at all, so pointing -resource-dir at $Final would be wrong.
    $ResourceDir = (& $ClangExe -print-resource-dir).Trim()

    $env:PATH = "$Install1\bin;C:\toolbox;$env:PATH"
    $env:CC   = $ClangExe
    $env:CXX  = $ClangxxExe

    $Projects = "clang;lld;clang-tools-extra"

    $cFlags = @(
        "-resource-dir=$ResourceDir"
    ) -join " "

    $cxxExtra = @(
        "-resource-dir=$ResourceDir",
        "-stdlib=libc++",
        "-unwindlib=libunwind",
        "-I$Final\include\c++\v1",
        "-L$RuntimeLibs",
        "-L$RuntimeLibsWin"
    ) -join " "

    $linkExtra = @(
        "-fuse-ld=lld",
        "-stdlib=libc++",
        "-unwindlib=libunwind",
        "--rtlib=compiler-rt",
        "-L$RuntimeLibs",
        "-L$RuntimeLibsWin",
        "-B$RuntimeLibs",
        "-B$RuntimeLibsWin"
    ) -join " "

    $extra = @(
        "-DCLANG_DEFAULT_CXX_STDLIB=libc++",
        "-DCLANG_DEFAULT_UNWINDLIB=libunwind",
    
        "-DCMAKE_C_COMPILER=$ClangExe",
        "-DCMAKE_CXX_COMPILER=$ClangxxExe",
        "-DCMAKE_C_FLAGS=$cFlags",
        "-DCMAKE_CXX_FLAGS=$cxxExtra",
        "-DLLVM_ENABLE_LIBCXX=ON",
        "-DCMAKE_EXE_LINKER_FLAGS=$linkExtra",
        "-DCMAKE_SHARED_LINKER_FLAGS=$linkExtra",
        "-DCLANG_DEFAULT_LINKER=lld",
        "-DCLANG_DEFAULT_RTLIB=compiler-rt"
    )

    $cmakeArgs = (Get-CommonLLVMCMakeArgs $Build2 $Final $Projects) + $extra

    Invoke-Build "Stage 2 (final)" $Build2 $Final $cmakeArgs $false
    
    $FinalClangExe = Join-Path $Final "bin\clang.exe"
    Install-CompilerRtBuiltins $FinalClangExe
    Write-ClangConfig
}

# ---------------------------------------------------------------------------
# Drive it
# ---------------------------------------------------------------------------

if ($Stage -eq 1 -or $Stage -eq 'All') {
    Run-Stage1
}

if ($Stage -eq 'Runtimes' -or $Stage -eq 'All') {
    Run-Runtimes
}

if ($Stage -eq 2 -or $Stage -eq 'All') {
    Run-Stage2
}

Write-Host ""
Write-Host "================================"
Write-Host "Done."
switch ($Stage) {
    1          { Write-Host "Stage 1 (bootstrap) compiler: $Install1" }
    'Runtimes' { Write-Host "Runtimes installed into: $Final" }
    default    { Write-Host "Final libc++-hosted toolchain: $Final"
                 Write-Host "Verify with: objdump -p `"$Final\bin\clang.exe`" | Select-String 'DLL Name'" }
}
Write-Host "================================"