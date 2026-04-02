[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\Xilinx\Vitis\2024.1",
    [string]$PlatformSwDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$appSrcDir = Join-Path $workspace "ax7020_udp_gateway_shadow_mirror_app\src"
$buildDir = Join-Path $workspace "ax7020_udp_gateway_shadow_mirror_app\build"
$objDir = Join-Path $buildDir "obj"
$gatewaySrcDir = Join-Path $workspace "vitis_2023_udp_gateway_ws_2\ax7020_udp_gateway_app\src"
$driverSource = Join-Path $workspace "dma_mvp_ps_driver_ref.c"
$driverHeader = Join-Path $workspace "dma_mvp_ps_driver_ref.h"
$contractHeader = Join-Path $workspace "dma_hw_regs.h"
$linkerScript = Join-Path $appSrcDir "lscript.ld"
$defaultSpecsFile = Join-Path $workspace "vitis_2023_udp_gateway_ws_2\ax7020_udp_gateway_app\Debug\Xilinx.spec"
$defaultWorkspaceRoot = Join-Path $workspace "ax7020_udp_gateway_shadow_mirror_platform_xsct\workspace"
$defaultPlatformName = "ax7020_udp_gateway_shadow_mirror_platform"
$legacyGatewayDomain = Join-Path $workspace "vitis_2023_udp_gateway_ws_2\ax7020_udp_gateway_platform\export\ax7020_udp_gateway_platform\sw\ax7020_udp_gateway_platform\standalone_domain"

function Resolve-ShadowApiBspRoot {
    param(
        [string]$WorkspaceRoot,
        [string]$PlatformName
    )

    $candidates = @(
        (Join-Path $WorkspaceRoot "$PlatformName\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0"),
        (Join-Path $WorkspaceRoot "standalone_bsp\ps7_cortexa9_0")
    )

    foreach ($candidate in $candidates) {
        if ((Test-Path $candidate) -and (Test-Path (Join-Path $candidate "include\xparameters.h"))) {
            return $candidate
        }
    }

    throw "No shadow mirror platform API BSP root found under $WorkspaceRoot. Run build_ax7020_udp_gateway_shadow_mirror_boot.ps1 first or pass -PlatformSwDir explicitly."
}

function Resolve-ShadowToolchainRoot {
    param(
        [string]$WorkspaceRoot,
        [string]$ApiBspRoot,
        [string]$PlatformName
    )

    $candidates = @(
        (Join-Path $WorkspaceRoot "$PlatformName\zynq_fsbl\zynq_fsbl_bsp\ps7_cortexa9_0"),
        (Join-Path $WorkspaceRoot "standalone_bsp\ps7_cortexa9_0")
    )

    foreach ($candidate in $candidates) {
        if ((Test-Path $candidate) -and (Test-Path (Join-Path $candidate "lib\libxil.a"))) {
            return $candidate
        }
    }

    $fallback = Get-ChildItem -Path $WorkspaceRoot -Recurse -File -Filter libxil.a -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $fallback) {
        return $fallback.Directory.Parent.FullName
    }

    throw "No shadow mirror toolchain BSP root with libxil.a found under $WorkspaceRoot"
}

function Resolve-WorkspaceRootFromApiBspRoot {
    param([string]$ApiBspRoot)

    $resolved = (Resolve-Path $ApiBspRoot).Path
    $marker = "\workspace\"
    $index = $resolved.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
    if ($index -ge 0) {
        return $resolved.Substring(0, $index + $marker.Length - 1)
    }

    return Split-Path -Parent (Split-Path -Parent $ApiBspRoot)
}

function Resolve-SpecsFile {
    param([string]$StartDir)

    $current = Resolve-Path $StartDir
    while ($null -ne $current) {
        $candidate = Join-Path $current.Path "Xilinx.spec"
        if (Test-Path $candidate) {
            return $candidate
        }

        $parent = Split-Path -Parent $current.Path
        if ([string]::IsNullOrWhiteSpace($parent) -or ($parent -eq $current.Path)) {
            break
        }
        $current = Resolve-Path $parent
    }

    throw "Xilinx.spec could not be resolved from platform root: $StartDir"
}

if ([string]::IsNullOrWhiteSpace($PlatformSwDir)) {
    $PlatformSwDir = Resolve-ShadowApiBspRoot -WorkspaceRoot $defaultWorkspaceRoot -PlatformName $defaultPlatformName
}

$workspaceRoot = Resolve-WorkspaceRootFromApiBspRoot -ApiBspRoot $PlatformSwDir
$toolchainRoot = Resolve-ShadowToolchainRoot -WorkspaceRoot $workspaceRoot -ApiBspRoot $PlatformSwDir -PlatformName $defaultPlatformName
$includeDir = Join-Path $PlatformSwDir "include"
$libDir = Join-Path $toolchainRoot "lib"
$legacyGatewayIncludeDir = Join-Path $legacyGatewayDomain "bspinclude\include"
$legacyGatewayLibDir = Join-Path $legacyGatewayDomain "bsplib\lib"
$gcc = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe"
$size = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-size.exe"
$specsFile = Resolve-SpecsFile -StartDir $toolchainRoot

foreach ($path in @(
    $appSrcDir,
    $gatewaySrcDir,
    $PlatformSwDir,
    $toolchainRoot,
    $includeDir,
    $libDir,
    $specsFile,
    $linkerScript,
    $gcc,
    $size,
    (Join-Path $appSrcDir "main.c"),
    (Join-Path $gatewaySrcDir "platform.c"),
    (Join-Path $gatewaySrcDir "udp_crypto_gateway.c"),
    $driverSource,
    $driverHeader,
    $contractHeader
)) {
    if (-not (Test-Path $path)) {
        throw "Required path not found: $path"
    }
}

if (Test-Path $buildDir) {
    Remove-Item -Recurse -Force $buildDir
}
New-Item -ItemType Directory -Force -Path $objDir | Out-Null

$specsFileArg = (Resolve-Path $specsFile).Path -replace "\\", "/"
$libDirs = [System.Collections.Generic.List[string]]::new()
$libDirs.Add((Resolve-Path $libDir).Path) | Out-Null

$includeDirs = @(
    $includeDir,
    $appSrcDir,
    $gatewaySrcDir,
    $workspace
)

$libraryIncludeDir = Join-Path (Split-Path -Parent $libDir) "include"
if ((Test-Path $libraryIncludeDir) -and ($libraryIncludeDir -ne $includeDir)) {
    $includeDirs += $libraryIncludeDir
}

if ((Test-Path $legacyGatewayIncludeDir) -and (Test-Path (Join-Path $legacyGatewayIncludeDir "netif\xadapter.h"))) {
    $includeDirs += $legacyGatewayIncludeDir
}

if (Test-Path $legacyGatewayLibDir) {
    $resolvedLegacyLibDir = (Resolve-Path $legacyGatewayLibDir).Path
    if (-not $libDirs.Contains($resolvedLegacyLibDir)) {
        $libDirs.Add($resolvedLegacyLibDir) | Out-Null
    }
}

$toolchainLibsrcDir = Join-Path $toolchainRoot "libsrc\standalone_v9_1\src"
if (Test-Path $toolchainLibsrcDir) {
    $includeDirs += $toolchainLibsrcDir
    foreach ($extraDir in @(
        (Join-Path $toolchainLibsrcDir "common"),
        (Join-Path $toolchainLibsrcDir "arm\cortexa9")
    )) {
        if (Test-Path $extraDir) {
            $includeDirs += $extraDir
        }
    }
}

$commonArgs = @(
    "-O2",
    "-DSDT",
    "-DUDP_GATEWAY_ENABLE_SHADOW_MIRROR=1",
    "-mcpu=cortex-a9",
    "-mfpu=vfpv3",
    "-mfloat-abi=hard",
    "-specs=$specsFileArg",
    "-ffunction-sections",
    "-fdata-sections",
    "-Wall",
    "-Wextra",
    "-U__clang__"
)

foreach ($dir in $includeDirs) {
    $commonArgs += "-I$dir"
}

$mainObj = Join-Path $objDir "main.o"
$platformObj = Join-Path $objDir "platform.o"
$gatewayObj = Join-Path $objDir "udp_crypto_gateway.o"
$driverObj = Join-Path $objDir "dma_mvp_ps_driver_ref.o"
$elfPath = Join-Path $buildDir "ax7020_udp_gateway_shadow_mirror_app.elf"
$mapPath = Join-Path $buildDir "ax7020_udp_gateway_shadow_mirror_app.map"
$libs = @()

if (Test-Path (Join-Path $libDir "libxilstandalone.a")) {
    $libs += "-lxilstandalone"
}
if (Test-Path (Join-Path $libDir "libxiltimer.a")) {
    $libs += "-lxiltimer"
}
if (Test-Path (Join-Path $libDir "libxil.a")) {
    $libs += "-lxil"
}
if (Test-Path (Join-Path $libDir "liblwip4.a")) {
    $libs += "-llwip4"
} elseif (Test-Path (Join-Path $legacyGatewayLibDir "liblwip4.a")) {
    $libs += "-llwip4"
}

if ($libs.Count -eq 0) {
    throw "No linkable Xilinx libraries were found under $libDir"
}

& $gcc @commonArgs -c (Join-Path $appSrcDir "main.c") -o $mainObj
if ($LASTEXITCODE -ne 0) {
    throw "Compile failed for shadow mirror main.c"
}

& $gcc @commonArgs -c (Join-Path $gatewaySrcDir "platform.c") -o $platformObj
if ($LASTEXITCODE -ne 0) {
    throw "Compile failed for platform.c"
}

& $gcc @commonArgs -c (Join-Path $gatewaySrcDir "udp_crypto_gateway.c") -o $gatewayObj
if ($LASTEXITCODE -ne 0) {
    throw "Compile failed for udp_crypto_gateway.c"
}

& $gcc @commonArgs -c $driverSource -o $driverObj
if ($LASTEXITCODE -ne 0) {
    throw "Compile failed for dma_mvp_ps_driver_ref.c"
}

$linkArgs = @(
    "-O2",
    "-mcpu=cortex-a9",
    "-mfpu=vfpv3",
    "-mfloat-abi=hard",
    "-specs=$specsFileArg",
    $mainObj,
    $platformObj,
    $gatewayObj,
    $driverObj,
    "-Wl,-T,$linkerScript",
    "-Wl,-Map,$mapPath",
    "-Wl,--gc-sections",
    "-o",
    $elfPath
)

foreach ($libSearchDir in $libDirs) {
    $linkArgs += "-L$($libSearchDir -replace '\\', '/')"
}

$linkArgs += "-Wl,--start-group"
$linkArgs += $libs
$linkArgs += @(
    "-lc",
    "-lgcc",
    "-lm",
    "-Wl,--end-group"
)

& $gcc @linkArgs
if ($LASTEXITCODE -ne 0) {
    throw "Link failed for shadow mirror app"
}

if (Test-Path $size) {
    & $size $elfPath
}

Write-Host "Built shadow mirror app ELF:"
Write-Host $elfPath
Write-Host "Platform API BSP root: $PlatformSwDir"
Write-Host "Toolchain BSP root: $toolchainRoot"
