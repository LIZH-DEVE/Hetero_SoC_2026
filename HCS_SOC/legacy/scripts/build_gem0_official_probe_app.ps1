[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\\Xilinx\\Vitis\\2024.1"
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceDir = Join-Path $workspace "gem0_official_probe_app\\src"
$buildDir = Join-Path $workspace "gem0_official_probe_app\\build"
$bspDir = Join-Path $workspace "platform\\export\\platform\\sw\\standalone_ps7_cortexa9_0"
$toolchain = Join-Path $bspDir "cortexa9_toolchain.cmake"
$cmake = Join-Path $VitisRoot "tps\\win64\\cmake-3.24.2\\bin\\cmake.exe"
$ninja = Join-Path $VitisRoot "tps\\win64\\lopper-1.1.0-packages\\min_sdk\\usr\\bin\\ninja.exe"
$gccBin = Join-Path $VitisRoot "gnu\\aarch32\\nt\\gcc-arm-none-eabi\\bin"
$eswRepo = Join-Path $VitisRoot "data\\embeddedsw"

if (-not (Test-Path $toolchain)) { throw "Toolchain file not found: $toolchain" }
if (-not (Test-Path $cmake)) { throw "CMake not found: $cmake" }
if (-not (Test-Path $ninja)) { throw "Ninja not found: $ninja" }
if (-not (Test-Path $gccBin)) { throw "GCC bin directory not found: $gccBin" }
if (-not (Test-Path $eswRepo)) { throw "ESW repo not found: $eswRepo" }

if (Test-Path $buildDir) {
    Remove-Item -Recurse -Force $buildDir
}
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$env:PATH = "$gccBin;$env:PATH"
$env:ESW_REPO = $eswRepo

function To-CMakePath {
    param([string]$PathValue)
    return ($PathValue -replace "\\", "/")
}

$sourceDirCMake = To-CMakePath $sourceDir
$buildDirCMake = To-CMakePath $buildDir
$toolchainCMake = To-CMakePath $toolchain
$bspDirCMake = To-CMakePath $bspDir
$includeDirCMake = To-CMakePath (Join-Path $bspDir "include")
$libDirCMake = To-CMakePath (Join-Path $bspDir "lib")
$specsCMake = To-CMakePath (Join-Path $bspDir "Xilinx.spec")
$ninjaCMake = To-CMakePath $ninja

$cmakeArgs = @(
    "-G", "Ninja",
    "-S", $sourceDirCMake,
    "-B", $buildDirCMake,
    "-DCMAKE_TOOLCHAIN_FILE=$toolchainCMake",
    "-DCMAKE_MODULE_PATH=$bspDirCMake",
    "-DCMAKE_INCLUDE_PATH=$includeDirCMake",
    "-DCMAKE_LIBRARY_PATH=$libDirCMake",
    "-DCMAKE_SPECS_FILE=$specsCMake",
    "-DCMAKE_MAKE_PROGRAM=$ninjaCMake"
)

& $cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed." }
& $ninja -C $buildDir
if ($LASTEXITCODE -ne 0) { throw "Ninja build failed." }

Write-Host "Built gem0_official_probe_app:"
Write-Host (Join-Path $buildDir "gem0_official_probe_app.elf")
