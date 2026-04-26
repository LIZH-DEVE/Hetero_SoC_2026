[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\VIVADO\Vitis\2023.1",
    [string]$PlatformSwDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$appSrcDir = Join-Path $workspace "ax7020_udp_gateway_shadow_mirror_app\src"
$buildDir = Join-Path $workspace "ax7020_udp_gateway_shadow_mirror_app\build"
$objDir = Join-Path $buildDir "obj"
$legacyWorkspaceRoot = Join-Path $workspace "legacy\workspaces\vitis_2023_udp_gateway_ws_2"
$gatewaySrcDir = Join-Path $legacyWorkspaceRoot "ax7020_udp_gateway_app\src"
$gatewaySource = Join-Path $gatewaySrcDir "udp_crypto_gateway.c"
$platformSource = Join-Path $gatewaySrcDir "platform.c"
$driverSource = Join-Path $workspace "dma_mvp_ps_driver_ref.c"
$driverHeader = Join-Path $workspace "dma_mvp_ps_driver_ref.h"
$contractHeader = Join-Path $workspace "dma_hw_regs.h"
$linkerScript = Join-Path $appSrcDir "lscript.ld"
$defaultSpecsFile = Join-Path $legacyWorkspaceRoot "ax7020_udp_gateway_app\Debug\Xilinx.spec"
$defaultWorkspaceRoot = Join-Path $workspace "ax7020_udp_gateway_shadow_mirror_platform_xsct\workspace"
$defaultPlatformName = "ax7020_udp_gateway_shadow_mirror_platform"
$legacyGatewayBspDir = Join-Path $legacyWorkspaceRoot "ax7020_udp_gateway_platform\ps7_cortexa9_0\standalone_domain\bsp"
$legacyGatewayBspProcessorRoot = Join-Path $legacyGatewayBspDir "ps7_cortexa9_0"
$legacyGatewayLwipSrcDir = Join-Path $legacyGatewayBspProcessorRoot "libsrc\lwip213_v1_0\src"
$legacyGatewayDomain = Join-Path $legacyWorkspaceRoot "ax7020_udp_gateway_platform\export\ax7020_udp_gateway_platform\sw\ax7020_udp_gateway_platform\standalone_domain"
$fallbackShadowLwipApiBspRoot = Join-Path $workspace "tmp_hsi_standalone_bsp_lwip\ps7_cortexa9_0"

function Resolve-ShadowApiBspRoot {
    param(
        [string]$WorkspaceRoot,
        [string]$PlatformName
    )

    $candidates = @(
        (Join-Path $WorkspaceRoot "$PlatformName\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0"),
        (Join-Path $WorkspaceRoot "standalone_bsp\ps7_cortexa9_0"),
        (Join-Path $WorkspaceRoot "$PlatformName\zynq_fsbl\zynq_fsbl_bsp\ps7_cortexa9_0")
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

    if ((Test-Path $ApiBspRoot) -and (Test-Path (Join-Path $ApiBspRoot "lib\libxil.a"))) {
        return (Resolve-Path $ApiBspRoot).Path
    }

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

function Get-ShadowLwipIncludeDirs {
    param([string]$ApiBspRoot)

    $resolved = [System.Collections.Generic.List[string]]::new()
    $libsrcRoot = Join-Path $ApiBspRoot "libsrc"
    if (-not (Test-Path $libsrcRoot)) {
        return @()
    }

    $lwipRoots = Get-ChildItem -Path (Join-Path $ApiBspRoot "libsrc") -Directory -Filter "lwip213_v*" -ErrorAction SilentlyContinue
    foreach ($lwipRoot in $lwipRoots) {
        foreach ($candidate in @(
            (Join-Path $lwipRoot.FullName "src\contrib\ports\xilinx\include"),
            (Join-Path $lwipRoot.FullName "src\lwip-2.1.3\src\include")
        )) {
            if (Test-Path $candidate) {
                $resolvedCandidate = (Resolve-Path $candidate).Path
                if (-not $resolved.Contains($resolvedCandidate)) {
                    $resolved.Add($resolvedCandidate) | Out-Null
                }
            }
        }
    }

    return $resolved.ToArray()
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

    foreach ($toolFallback in @(
        (Join-Path $VitisRoot "data\embeddedsw\scripts\specs\arm\Xilinx.spec"),
        (Join-Path $VitisRoot "data\embeddedsw-sdt\scripts\specs\arm\Xilinx.spec")
    )) {
        if (Test-Path $toolFallback) {
            return (Resolve-Path $toolFallback).Path
        }
    }

    throw "Xilinx.spec could not be resolved from platform root: $StartDir"
}

function Resolve-GnuMakePath {
    param([string]$VitisRoot)

    $candidate = Join-Path $VitisRoot "gnuwin\bin\make.exe"
    if (Test-Path $candidate) {
        return (Resolve-Path $candidate).Path
    }

    $fallback = Get-Command make -ErrorAction SilentlyContinue
    if ($null -ne $fallback) {
        return $fallback.Source
    }

    throw "GNU make not found. Expected Vitis gnuwin make.exe under $VitisRoot"
}

function Update-LegacyLwipLibrary {
    param(
        [string]$VitisRoot,
        [string]$GccPath,
        [string]$LegacyGatewayLwipSrcDir,
        [string]$LegacyGatewayBspLibDir,
        [string]$LegacyGatewayExportLwipLib,
        [string]$LegacyGatewayLwipSource
    )

    if (-not (Test-Path $LegacyGatewayLwipSrcDir)) {
        return
    }

    if (-not (Test-Path $LegacyGatewayLwipSource)) {
        return
    }

    $makeExe = Resolve-GnuMakePath -VitisRoot $VitisRoot
    $gccBinDir = Split-Path -Parent $GccPath
    $lwipLib = Join-Path $LegacyGatewayBspLibDir "liblwip4.a"
    $originalPath = $env:PATH

    try {
        $env:PATH = "$gccBinDir;$(Split-Path -Parent $makeExe);$originalPath"
        $makeArgs = @(
            "--no-print-directory",
            "-C", $LegacyGatewayLwipSrcDir,
            "",
            "SHELL=CMD",
            "GCC_COMPILER=arm-none-eabi-gcc",
            "COMPILER=arm-none-eabi-gcc",
            "ASSEMBLER=arm-none-eabi-as",
            "ARCHIVER=arm-none-eabi-ar",
            "COMPILER_FLAGS=  -O2 -c",
            "EXTRA_COMPILER_FLAGS=-mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -nostartfiles -g -Wall -Wextra -fno-tree-loop-distribute-patterns"
        )

        $makeArgs[3] = "clean"
        & $makeExe @makeArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clean legacy lwIP objects under $LegacyGatewayLwipSrcDir"
        }

        $makeArgs[3] = "libs"
        & $makeExe @makeArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to rebuild legacy lwIP BSP library under $LegacyGatewayLwipSrcDir"
        }
    }
    finally {
        $env:PATH = $originalPath
    }

    if (-not (Test-Path $lwipLib)) {
        throw "Legacy lwIP BSP library was not produced: $lwipLib"
    }

    if (-not [string]::IsNullOrWhiteSpace($LegacyGatewayExportLwipLib)) {
        $exportDir = Split-Path -Parent $LegacyGatewayExportLwipLib
        if (Test-Path $exportDir) {
            Copy-Item -Path $lwipLib -Destination $LegacyGatewayExportLwipLib -Force
        }
    }
}

if ([string]::IsNullOrWhiteSpace($PlatformSwDir)) {
    $PlatformSwDir = Resolve-ShadowApiBspRoot -WorkspaceRoot $defaultWorkspaceRoot -PlatformName $defaultPlatformName
}

$workspaceRoot = Resolve-WorkspaceRootFromApiBspRoot -ApiBspRoot $PlatformSwDir
$toolchainRoot = Resolve-ShadowToolchainRoot -WorkspaceRoot $workspaceRoot -ApiBspRoot $PlatformSwDir -PlatformName $defaultPlatformName
$includeDir = Join-Path $PlatformSwDir "include"
$libDir = Join-Path $toolchainRoot "lib"
$fallbackShadowLwipIncludeDir = Join-Path $fallbackShadowLwipApiBspRoot "include"
$fallbackShadowLwipLibDir = Join-Path $fallbackShadowLwipApiBspRoot "lib"
$legacyGatewayBspIncludeDir = Join-Path $legacyGatewayBspProcessorRoot "include"
$legacyGatewayBspLibDir = Join-Path $legacyGatewayBspProcessorRoot "lib"
$legacyGatewayLwipSource = Join-Path $legacyGatewayBspProcessorRoot "libsrc\lwip213_v1_0\src\contrib\ports\xilinx\netif\xemacpsif.c"
$legacyGatewayIncludeDir = Join-Path $legacyGatewayDomain "bspinclude\include"
$legacyGatewayLibDir = Join-Path $legacyGatewayDomain "bsplib\lib"
$legacyGatewayExportLwipLib = Join-Path $legacyGatewayLibDir "liblwip4.a"
$gcc = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe"
$size = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-size.exe"
$specsFile = Resolve-SpecsFile -StartDir $toolchainRoot

foreach ($path in @(
    $appSrcDir,
    $PlatformSwDir,
    $toolchainRoot,
    $includeDir,
    $libDir,
    $specsFile,
    $linkerScript,
    $gcc,
    $size,
    (Join-Path $appSrcDir "main.c"),
    $driverSource,
    $driverHeader,
    $contractHeader
)) {
    if (-not (Test-Path $path)) {
        throw "Required path not found: $path"
    }
}

$mainObj = Join-Path $objDir "main.o"
$platformObj = Join-Path $objDir "platform.o"
$gatewayObj = Join-Path $objDir "udp_crypto_gateway.o"
$driverObj = Join-Path $objDir "dma_mvp_ps_driver_ref.o"
$elfPath = Join-Path $buildDir "ax7020_udp_gateway_shadow_mirror_app.elf"
$mapPath = Join-Path $buildDir "ax7020_udp_gateway_shadow_mirror_app.map"

$canCompilePlatform = Test-Path $platformSource
$canCompileGateway = Test-Path $gatewaySource
$reusePrebuiltPlatformObj = (-not $canCompilePlatform) -and (Test-Path $platformObj)
$reusePrebuiltGatewayObj = (-not $canCompileGateway) -and (Test-Path $gatewayObj)

if ((-not $canCompilePlatform) -and (-not $reusePrebuiltPlatformObj)) {
    throw "Required platform source/object not found: $platformSource or $platformObj"
}
if ((-not $canCompileGateway) -and (-not $reusePrebuiltGatewayObj)) {
    throw "Required gateway source/object not found: $gatewaySource or $gatewayObj"
}

Update-LegacyLwipLibrary `
    -VitisRoot $VitisRoot `
    -GccPath $gcc `
    -LegacyGatewayLwipSrcDir $legacyGatewayLwipSrcDir `
    -LegacyGatewayBspLibDir $legacyGatewayBspLibDir `
    -LegacyGatewayExportLwipLib $legacyGatewayExportLwipLib `
    -LegacyGatewayLwipSource $legacyGatewayLwipSource

if (Test-Path $buildDir) {
    if ($reusePrebuiltPlatformObj -or $reusePrebuiltGatewayObj) {
        Write-Host "Reusing prebuilt legacy objects from existing build directory."
    } else {
        Remove-Item -Recurse -Force $buildDir
    }
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

if ((Test-Path $legacyGatewayBspIncludeDir) -and (Test-Path (Join-Path $legacyGatewayBspIncludeDir "netif\xadapter.h"))) {
    $includeDirs += $legacyGatewayBspIncludeDir
}

if ((Test-Path $legacyGatewayIncludeDir) -and (Test-Path (Join-Path $legacyGatewayIncludeDir "netif\xadapter.h"))) {
    $includeDirs += $legacyGatewayIncludeDir
}

$platformLwipIncludeDirs = Get-ShadowLwipIncludeDirs -ApiBspRoot $PlatformSwDir
foreach ($platformLwipIncludeDir in $platformLwipIncludeDirs) {
    $includeDirs += $platformLwipIncludeDir
}

if ((Test-Path $fallbackShadowLwipIncludeDir) -and (Test-Path (Join-Path $fallbackShadowLwipIncludeDir "netif\xadapter.h"))) {
    $includeDirs += $fallbackShadowLwipIncludeDir
}

$fallbackShadowLwipIncludeDirs = Get-ShadowLwipIncludeDirs -ApiBspRoot $fallbackShadowLwipApiBspRoot
foreach ($fallbackShadowLwipIncludeDir in $fallbackShadowLwipIncludeDirs) {
    $includeDirs += $fallbackShadowLwipIncludeDir
}

$libraryIncludeDir = Join-Path (Split-Path -Parent $libDir) "include"
if ((Test-Path $libraryIncludeDir) -and ($libraryIncludeDir -ne $includeDir)) {
    $includeDirs += $libraryIncludeDir
}

if (Test-Path $legacyGatewayBspLibDir) {
    $resolvedLegacyBspLibDir = (Resolve-Path $legacyGatewayBspLibDir).Path
    if (-not $libDirs.Contains($resolvedLegacyBspLibDir)) {
        $libDirs.Add($resolvedLegacyBspLibDir) | Out-Null
    }
}

if (Test-Path $legacyGatewayLibDir) {
    $resolvedLegacyLibDir = (Resolve-Path $legacyGatewayLibDir).Path
    if (-not $libDirs.Contains($resolvedLegacyLibDir)) {
        $libDirs.Add($resolvedLegacyLibDir) | Out-Null
    }
}

if ((Test-Path $fallbackShadowLwipLibDir) -and (Test-Path (Join-Path $fallbackShadowLwipLibDir "liblwip4.a"))) {
    $resolvedFallbackShadowLwipLibDir = (Resolve-Path $fallbackShadowLwipLibDir).Path
    if (-not $libDirs.Contains($resolvedFallbackShadowLwipLibDir)) {
        $libDirs.Add($resolvedFallbackShadowLwipLibDir) | Out-Null
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
} elseif (Test-Path (Join-Path $fallbackShadowLwipLibDir "liblwip4.a")) {
    $libs += "-llwip4"
}

if ($libs.Count -eq 0) {
    throw "No linkable Xilinx libraries were found under $libDir"
}

& $gcc @commonArgs -c (Join-Path $appSrcDir "main.c") -o $mainObj
if ($LASTEXITCODE -ne 0) {
    throw "Compile failed for shadow mirror main.c"
}

if ($canCompilePlatform) {
    & $gcc @commonArgs -c $platformSource -o $platformObj
    if ($LASTEXITCODE -ne 0) {
        throw "Compile failed for platform.c"
    }
} else {
    Write-Host "Using prebuilt platform object:"
    Write-Host $platformObj
}

if ($canCompileGateway) {
    & $gcc @commonArgs -c $gatewaySource -o $gatewayObj
    if ($LASTEXITCODE -ne 0) {
        throw "Compile failed for udp_crypto_gateway.c"
    }
} else {
    Write-Host "Using prebuilt udp_crypto_gateway object:"
    Write-Host $gatewayObj
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
