param(
    [switch]$Update      = $false,
    [switch]$Clang       = $false,
    [switch]$MSVC        = $false,
    [switch]$Clean       = $false,
    [switch]$Reconfigure = $false
)

$ErrorActionPreference = "Stop"

$Repo = "https://github.com/llvm/llvm-project.git"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

$Source      = Join-Path $Root "llvm-project"
$BuildRoot   = Join-Path $Root "llvm\build"
$InstallRoot = Join-Path $Root "llvm\install"

$Compiler = if($Clang) {"clang"} elseif($MSVC) {"msvc"} else {"mingw"}

$Build   = Join-Path $BuildRoot $Compiler
$Install = Join-Path $InstallRoot $Compiler
# $Install  = "C:\llvm"

function Require-Tool($name)
{
    if(-not (Get-Command $name -ErrorAction SilentlyContinue))
    {
        throw "$name not found."
    }
}

function Run($cmd)
{
    Write-Host ">" $cmd
    Invoke-Expression $cmd

    if($LASTEXITCODE)
    {
        throw "$cmd failed"
    }
}

Require-Tool git
Require-Tool cmake
Require-Tool ninja

function Enable-MSVCEnvironment
{
    if (Get-Command cl.exe -ErrorAction SilentlyContinue)
    {
        return
    }

    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

    if (!(Test-Path $vswhere))
    {
        throw "Visual Studio not found"
    }

    $VSPath = & $vswhere `
        -latest `
        -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath

    if (!$VSPath)
    {
        throw "MSVC tools missing"
    }

    $DevCmd = Join-Path $VSPath "Common7\Tools\VsDevCmd.bat"

    cmd /c "`"$DevCmd`" -arch=x64 && set" | ForEach-Object {
        if ($_ -match "^(.*?)=(.*)$")
        {
            Set-Item "env:$($matches[1])" $matches[2]
        }
    }
}

if($Clang)
{
   $ClangBin = Join-Path $InstallRoot "mingw\bin"

   $env:PATH = ($env:PATH -split ';' |
       Where-Object { $_ -ne 'C:\mingw64\bin' }) -join ';'

   $env:PATH = "$ClangBin;C:\mingw64\bin;$env:PATH"

   $env:CC="clang"
   $env:CXX="clang++"

   $Config   = "Release"

   $Projects = "clang;clang-tools-extra;lld"
   $Runtimes = "compiler-rt;libunwind;libcxx;libcxxabi"
}
elseif($MSVC) {
   Enable-MSVCEnvironment
       
   $Config = "Release"
   
   $Projects = "clang;clang-tools-extra;lld;lldb"
   $Runtimes = "libcxx;libcxxabi"

   Remove-Item Env:CC  -ErrorAction Ignore
   Remove-Item Env:CXX -ErrorAction Ignore
   $env:CC  = "cl"
   $env:CXX = "cl"

   Require-Tool cl
   Require-Tool link
}
else
{
   $env:PATH = "C:\mingw64\bin;$env:PATH"
   
   Require-Tool gcc
   Require-Tool g++

   $Config = "Release"

   $Projects = "clang;lld"
   $Runtimes = ""

   $env:CC="gcc"
   $env:CXX="g++"
}

$env:CMAKE_COLOR_DIAGNOSTICS="ON"
$env:NINJA_STATUS="[%f/%t | %p | %r running | %w elapsed] "

if($Clean)
{
    if(Test-Path $Build)
    {
        Write-Host "Removing $Build"
        Remove-Item $Build -Recurse -Force
    }

    if(Test-Path $Install)
    {
        Write-Host "Removing $Install"
        Remove-Item $Install -Recurse -Force
    }
}

if(!(Test-Path "$Source\.git"))
{
    git clone --depth=1 $Repo $Source
}

if($Update)
{
    Push-Location $Source

    git pull --rebase

    Pop-Location
}
else
{
    Write-Host "Repository update skipped."
}

Push-Location $Source
$Commit = git rev-parse HEAD
Pop-Location

$sccache = @()

if(Get-Command sccache -ErrorAction SilentlyContinue)
{
    Write-Host "sccache enabled"

    $sccache += "-DCMAKE_C_COMPILER_LAUNCHER=sccache"
    $sccache += "-DCMAKE_CXX_COMPILER_LAUNCHER=sccache"
}

if($Reconfigure)
{
    Remove-Item "$Build/CMakeCache.txt" -Force -ErrorAction Ignore
    Remove-Item "$Build/CMakeFiles" -Recurse -Force -ErrorAction Ignore
}

Write-Host "Running CMake configuration"

$LinkJobs = [Math]::Max(1, [Math]::Ceiling([Environment]::ProcessorCount / 8))

$cmakeArgs = @(
   "-G",
   "Ninja",
   "-S",
   "$Source\llvm",
   "-B",
   $Build,
   "-DCMAKE_BUILD_TYPE=$Config",
   "-DCMAKE_INSTALL_PREFIX=$Install",
   "-DLLVM_ENABLE_PROJECTS=$Projects",
   "-DLLVM_ENABLE_RUNTIMES=$Runtimes",
   "-DLIBCXX_ENABLE_STD_MODULES=ON",
   "-DLIBCXX_INSTALL_MODULES=ON",
   "-DLIBCXX_ENABLE_FILESYSTEM=ON",
   "-DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=ON",
   "-DLLVM_TARGETS_TO_BUILD=host",
   "-DLLDB_ENABLE_PYTHON=OFF",
   "-DLLVM_ENABLE_ASSERTIONS=OFF",
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
   "-DLLVM_INSTALL_UTILS=ON",
   "-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON",
   "-DCMAKE_C_FLAGS_RELEASE=-O3",
   "-DCMAKE_CXX_FLAGS_RELEASE=-O3",
   "-DLIBCXX_ENABLE_SHARED=OFF",
   "-DLIBCXXABI_ENABLE_SHARED=OFF",
   "-DLIBUNWIND_ENABLE_SHARED=OFF",
   "-DLIBCXX_ENABLE_STATIC=ON",
   "-DLIBCXXABI_ENABLE_STATIC=ON",
   "-DLIBUNWIND_ENABLE_STATIC=ON",
   "-DLLVM_PARALLEL_LINK_JOBS=$LinkJobs"
)

if($Clang)
{
   $RuntimeArgs = @(
   "-DCMAKE_C_FLAGS=-static"
   "-DCMAKE_CXX_FLAGS=-static"
   "-DCMAKE_EXE_LINKER_FLAGS=-static -fuse-ld=lld"
   "-DCMAKE_SHARED_LINKER_FLAGS=-static -fuse-ld=lld"
   ) -join ";"
   $CMakeArgs += "-DRUNTIMES_CMAKE_ARGS=$RuntimeArgs"
   
   $flags = "-static -fuse-ld=lld -lwinpthread"
   $cmakeArgs += @(
      "-DCLANG_DEFAULT_LINKER=lld",
      "-DLLVM_ENABLE_LIBCXX=ON",
      "-DCLANG_DEFAULT_CXX_STDLIB=libc++",
      "-DCMAKE_CXX_FLAGS=-Wno-everything",
      "-DCMAKE_C_FLAGS=-Wno-everything",
      "-DCMAKE_C_COMPILER=$ClangBin\clang.exe",
      "-DCMAKE_CXX_COMPILER=$ClangBin\clang++.exe",
      "-DRUNTIMES_CMAKE_ARGS=-DCMAKE_EXE_LINKER_FLAGS=-lwinpthread",
      "-DCMAKE_LINKER=$ClangBin\ld-lld.exe",
      "-DLLVM_BUILD_LLVM_DYLIB=OFF",
      "-DLLVM_LINK_LLVM_DYLIB=OFF",
      "-DBUILD_SHARED_LIBS=OFF",
      "-DCMAKE_EXE_LINKER_FLAGS=$flags"
      "-DCMAKE_SHARED_LINKER_FLAGS=$flags",
      "-DCMAKE_MODULE_LINKER_FLAGS=$flags"
   )
}
elseif($MSVC)
{
    $cmakeArgs += @(
        "-DCMAKE_C_COMPILER=cl",
        "-DCMAKE_CXX_COMPILER=cl",
        "-DCMAKE_C_FLAGS=/W4",
        "-DCMAKE_CXX_FLAGS=/W4",
        "-DCMAKE_C_FLAGS_RELEASE=/O2",
        "-DCMAKE_CXX_FLAGS_RELEASE=/O2",
        "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded"
    )
}
else
{
   $flags = "-static -static-libgcc -static-libstdc++ -Wl,-Bstatic -lwinpthread -Wl,-Bdynamic"
   $cmakeArgs += @(
      "-DCMAKE_C_FLAGS=-w",
      "-DCMAKE_CXX_FLAGS=-w",
      "-DCMAKE_C_COMPILER_TARGET=x86_64-w64-windows-gnu",
      "-DCMAKE_CXX_COMPILER_TARGET=x86_64-w64-windows-gnu",
      "-DCMAKE_EXE_LINKER_FLAGS=$flags"
   )
}

$cmakeArgs += $sccache

cmake @cmakeArgs

if($LASTEXITCODE)
{
   throw "CMake configuration failed"
}


$jobs = [Environment]::ProcessorCount

cmake --build $Build --target install --parallel $jobs -- -d stats

if ($LASTEXITCODE)
{
    throw "Build failed."
}

$Commit | Set-Content "$Build\.llvm_commit"

Write-Host ""
Write-Host "================================"
Write-Host "LLVM installed:"
Write-Host $Install
Write-Host "================================"
