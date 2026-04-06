[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\Xilinx\Vitis\2023.1"
)

$ErrorActionPreference = "Stop"

function Add-Unique {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )

    if (-not $List.Contains($Value)) {
        $List.Add($Value) | Out-Null
    }
}

function Resolve-DriverSrcDir {
    param(
        [string]$BspRoot,
        [string]$DriverName,
        [string]$LegacyDirName = $null
    )

    $candidates = @()
    if ($LegacyDirName) {
        $candidates += (Join-Path $BspRoot "libsrc\$LegacyDirName\src")
    }
    $candidates += (Join-Path $BspRoot "libsrc\$DriverName\src")
    $candidates += (Join-Path $BspRoot "libsrc\$DriverName")

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "Unable to resolve source directory for driver '$DriverName' under $BspRoot"
}

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$appSrcDir = Join-Path $workspace "ax7020_official_net_test_app\src"
$manualBuildDir = Join-Path $workspace "ax7020_official_net_test_app\manual_build_design1"
$objDir = Join-Path $manualBuildDir "obj"
$elfPath = Join-Path $manualBuildDir "ax7020_udp_gateway_design1_app.elf"
$mapPath = Join-Path $manualBuildDir "ax7020_udp_gateway_design1_app.map"

$platformBspRoot = Join-Path $workspace "vitis_2023_udp_gateway_ws_design1\ax7020_udp_gateway_platform_design1\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0"
$workingBspLibRoot = Join-Path $workspace "vitis_2023_udp_gateway_ws_design1\ax7020_udp_gateway_platform_design1\export\ax7020_udp_gateway_platform_design1\sw\ax7020_udp_gateway_platform_design1\standalone_domain\bsplib\lib"
$platformInclude = Join-Path $platformBspRoot "include"
$generatedStandaloneRoot = Join-Path $platformBspRoot "libsrc\standalone_v8_1\src"
$embeddedswStandaloneRoot = Join-Path $VitisRoot "data\embeddedsw\lib\bsp\standalone_v8_1\src"
$standaloneCommonDir = Join-Path $embeddedswStandaloneRoot "common"
$standaloneArmCommonDir = Join-Path $embeddedswStandaloneRoot "arm\common"
$standaloneGccCommonDir = Join-Path $embeddedswStandaloneRoot "arm\common\gcc"
$standaloneArchDir = Join-Path $embeddedswStandaloneRoot "arm\cortexa9"
$scugicSrcDir = Resolve-DriverSrcDir -BspRoot $platformBspRoot -DriverName "scugic" -LegacyDirName "scugic_v5_1"
$scutimerSrcDir = Resolve-DriverSrcDir -BspRoot $platformBspRoot -DriverName "scutimer" -LegacyDirName "scutimer_v2_4"
$emacpsSrcDir = Resolve-DriverSrcDir -BspRoot $platformBspRoot -DriverName "emacps" -LegacyDirName "emacps_v3_18"
$toolchainLibDir = $workingBspLibRoot
$linkerScript = Join-Path $appSrcDir "lscript.ld"
$specsFile = Join-Path $VitisRoot "data\embeddedsw-sdt\scripts\specs\arm\Xilinx.spec"
$gcc = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe"
$size = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-size.exe"

foreach ($path in @(
    $appSrcDir,
    $platformBspRoot,
    $platformInclude,
    $generatedStandaloneRoot,
    $embeddedswStandaloneRoot,
    $standaloneCommonDir,
    $standaloneArmCommonDir,
    $standaloneArchDir,
    $scugicSrcDir,
    $scutimerSrcDir,
    $emacpsSrcDir,
    $standaloneGccCommonDir,
    $toolchainLibDir,
    $linkerScript,
    $specsFile,
    $gcc
)) {
    if (-not (Test-Path $path)) {
        throw "Required path not found: $path"
    }
}

if (Test-Path $manualBuildDir) {
    Remove-Item -Recurse -Force $manualBuildDir
}
New-Item -ItemType Directory -Force -Path $objDir | Out-Null

$includeArgs = [System.Collections.Generic.List[string]]::new()
foreach ($inc in @(
    $platformInclude,
    $generatedStandaloneRoot,
    $standaloneCommonDir,
    $standaloneArmCommonDir,
    $standaloneArchDir,
    $scugicSrcDir,
    $scutimerSrcDir,
    $emacpsSrcDir,
    $standaloneGccCommonDir
)) {
    Add-Unique -List $includeArgs -Value "-I$inc"
}

$commonCompileArgs = @(
    "-O2",
    "-DXIL_INTERRUPT",
    "-mcpu=cortex-a9",
    "-mfpu=vfpv3",
    "-mfloat-abi=hard",
    "-specs=$specsFile",
    "-Wall",
    "-Wextra",
    "-Os",
    "-ffunction-sections",
    "-fdata-sections",
    "-U__clang__"
)

$appSources = @(
    (Join-Path $appSrcDir "main.c"),
    (Join-Path $appSrcDir "platform_zynq.c"),
    (Join-Path $appSrcDir "udp_crypto_gateway.c")
)

$allSources = @($appSources)
$objects = [System.Collections.Generic.List[string]]::new()

foreach ($src in $allSources) {
    if (-not (Test-Path $src)) {
        throw "Source file not found: $src"
    }

    $objName = "{0}_{1}.o" -f [IO.Path]::GetFileNameWithoutExtension($src), ([Math]::Abs($src.GetHashCode()))
    $objPath = Join-Path $objDir $objName
    $compileArgs = @()
    $compileArgs += $includeArgs
    $compileArgs += $commonCompileArgs
    $compileArgs += @("-c", $src, "-o", $objPath)

    & $gcc @compileArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Compile failed: $src"
    }

    $objects.Add($objPath) | Out-Null
}

$linkArgs = @()
$linkArgs += $commonCompileArgs
$linkArgs += $objects
$linkArgs += @(
    "-Wl,-T,$linkerScript",
    "-Wl,-Map,$mapPath",
    "-Wl,--gc-sections",
    "-L$toolchainLibDir",
    "-Wl,--start-group",
    "-llwip4",
    "-lxil",
    "-lc",
    "-lgcc",
    "-lm",
    "-Wl,--end-group",
    "-o",
    $elfPath
)

& $gcc @linkArgs
if ($LASTEXITCODE -ne 0) {
    throw "Link failed."
}

if (Test-Path $size) {
    & $size $elfPath
}

Write-Host "Built design1 manual Stage A app:"
Write-Host $elfPath
