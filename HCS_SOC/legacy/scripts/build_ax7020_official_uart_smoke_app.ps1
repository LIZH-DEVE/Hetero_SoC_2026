[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\\Xilinx\\Vitis\\2024.1",
    [string]$OfficialRoot = "D:\\FPGAhanjia\\Hetero_SoC_2026_3\\AX7020_2023.1\\course_s2_vitis\\06_net_test\\Vitis\\design_1_wrapper"
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceDir = Join-Path $workspace "ax7020_official_uart_smoke_app\\src"
$buildDir = Join-Path $workspace "ax7020_official_uart_smoke_app\\build"
$bspDir = Join-Path $OfficialRoot "ps7_cortexa9_0\\standalone_domain\\bsp\\ps7_cortexa9_0"
$platformSwDir = Join-Path $workspace "platform\\export\\platform\\sw\\standalone_ps7_cortexa9_0"
$toolchain = Join-Path $platformSwDir "cortexa9_toolchain.cmake"
$cmake = Join-Path $VitisRoot "tps\\win64\\cmake-3.24.2\\bin\\cmake.exe"
$ninja = Join-Path $VitisRoot "tps\\win64\\lopper-1.1.0-packages\\min_sdk\\usr\\bin\\ninja.exe"
$gccBin = Join-Path $VitisRoot "gnu\\aarch32\\nt\\gcc-arm-none-eabi\\bin"
$eswRepo = Join-Path $VitisRoot "data\\embeddedsw"
$cmakeModules = Join-Path $eswRepo "cmake"
$includeDir = Join-Path $bspDir "include"
$libDir = Join-Path $platformSwDir "lib"

foreach ($pathInfo in @(
    @{ Label = "Source directory"; Path = $sourceDir },
    @{ Label = "Official BSP directory"; Path = $bspDir },
    @{ Label = "Platform software directory"; Path = $platformSwDir },
    @{ Label = "Toolchain file"; Path = $toolchain },
    @{ Label = "CMake"; Path = $cmake },
    @{ Label = "Ninja"; Path = $ninja },
    @{ Label = "GCC bin directory"; Path = $gccBin },
    @{ Label = "ESW repo"; Path = $eswRepo },
    @{ Label = "ESW CMake modules"; Path = $cmakeModules }
)) {
    if (-not (Test-Path $pathInfo.Path)) {
        throw "$($pathInfo.Label) not found: $($pathInfo.Path)"
    }
}

New-Item -ItemType Directory -Force -Path $libDir | Out-Null

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
$platformSwDirCMake = To-CMakePath $platformSwDir
$cmakeModulesCMake = To-CMakePath $cmakeModules
$includeDirCMake = To-CMakePath $includeDir
$libDirCMake = To-CMakePath $libDir
$specsCMake = To-CMakePath (Join-Path $eswRepo "scripts\\specs\\arm\\Xilinx.spec")
$ninjaCMake = To-CMakePath $ninja

$cmakeArgs = @(
    "-G", "Ninja",
    "-S", $sourceDirCMake,
    "-B", $buildDirCMake,
    "-DCMAKE_TOOLCHAIN_FILE=$toolchainCMake",
    "-DCMAKE_MODULE_PATH=$cmakeModulesCMake;$bspDirCMake",
    "-DCMAKE_INCLUDE_PATH=$includeDirCMake",
    "-DCMAKE_LIBRARY_PATH=$libDirCMake",
    "-DCMAKE_SPECS_FILE=$specsCMake",
    "-DCMAKE_MAKE_PROGRAM=$ninjaCMake",
    "-DOFFICIAL_BSP_ROOT=$bspDirCMake",
    "-DPLATFORM_SW_ROOT=$platformSwDirCMake"
)

& $cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) {
    throw "CMake configure failed."
}

& $ninja -C $buildDir
if ($LASTEXITCODE -ne 0) {
    throw "Ninja build failed."
}

Write-Host "Built ax7020_official_uart_smoke_app:"
Write-Host (Join-Path $buildDir "ax7020_official_uart_smoke_app.elf")
