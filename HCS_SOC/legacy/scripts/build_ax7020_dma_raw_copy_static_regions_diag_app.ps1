[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\Xilinx\Vitis\2024.1",
    [Parameter(Mandatory = $true)]
    [string]$PlatformSwDir,
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$appSrcDir = Join-Path $workspace "ax7020_dma_raw_copy_static_regions_diag_app\src"
$mainSource = Join-Path $appSrcDir "main.c"
$linkerScript = Join-Path $appSrcDir "lscript.ld"

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $workspace "ax7020_dma_raw_copy_static_regions_diag_app\build"
}

$buildDir = $OutputDir
$objDir = Join-Path $buildDir "obj"
$gcc = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe"
$size = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-size.exe"
$elfPath = Join-Path $buildDir "ax7020_dma_raw_copy_static_regions_diag_app.elf"
$mapPath = Join-Path $buildDir "ax7020_dma_raw_copy_static_regions_diag_app.map"
$mainObj = Join-Path $objDir "main.o"

function Resolve-WorkspaceRootFromApiBspRoot {
    param([string]$ApiBspRoot)

    $resolved = (Resolve-Path $ApiBspRoot).Path
    $marker = "\ax7020_dma_raw_copy_platform_xsct\workspace\"
    $index = $resolved.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
    if ($index -ge 0) {
        return $resolved.Substring(0, $index + $marker.Length - 1)
    }

    throw "Workspace root could not be resolved from API BSP root: $ApiBspRoot"
}

function Resolve-PlatformToolchainRoot {
    param([string]$WorkspaceRoot)

    $candidate = Join-Path $WorkspaceRoot "ax7020_dma_raw_copy_platform\zynq_fsbl\zynq_fsbl_bsp\ps7_cortexa9_0"
    if ((Test-Path $candidate) -and (Test-Path (Join-Path $candidate "lib\libxil.a"))) {
        return $candidate
    }

    throw "Dedicated raw-copy toolchain BSP root with libxil.a not found under $WorkspaceRoot"
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

$workspaceRoot = Resolve-WorkspaceRootFromApiBspRoot -ApiBspRoot $PlatformSwDir
$toolchainRoot = Resolve-PlatformToolchainRoot -WorkspaceRoot $workspaceRoot
$includeDir = Join-Path $PlatformSwDir "include"
$libDir = Join-Path $toolchainRoot "lib"
$specsFile = Resolve-SpecsFile -StartDir $toolchainRoot
$specsFileArg = $specsFile -replace '\\', '/'
$libDirArg = $libDir -replace '\\', '/'
$includeDirs = @($workspace, $includeDir)
$libraryIncludeDir = Join-Path (Split-Path -Parent $libDir) "include"
if ((Test-Path $libraryIncludeDir) -and ($libraryIncludeDir -ne $includeDir)) {
    $includeDirs += $libraryIncludeDir
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

foreach ($path in @(
    $PlatformSwDir,
    $toolchainRoot,
    $includeDir,
    $libDir,
    $specsFile,
    $mainSource,
    $linkerScript,
    $gcc,
    (Join-Path $workspace "dma_hw_regs.h"),
    (Join-Path $workspace "dma_mvp_ps_driver_ref.h")
)) {
    if (-not (Test-Path $path)) {
        throw "Required path not found: $path"
    }
}

if (Test-Path $buildDir) {
    Remove-Item -Recurse -Force $buildDir
}
New-Item -ItemType Directory -Force -Path $objDir | Out-Null

$commonArgs = @(
    "-O2",
    "-DSDT",
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

if ($libs.Count -eq 0) {
    throw "No linkable Xilinx libraries were found under $libDir"
}

& $gcc @commonArgs -c $mainSource -o $mainObj
if ($LASTEXITCODE -ne 0) {
    throw "Compile failed for raw-copy static-regions diagnostic main.c"
}

$linkArgs = @(
    "-O2",
    "-mcpu=cortex-a9",
    "-mfpu=vfpv3",
    "-mfloat-abi=hard",
    "-specs=$specsFileArg",
    $mainObj,
    "-Wl,-T,$linkerScript",
    "-Wl,-Map,$mapPath",
    "-Wl,--gc-sections",
    "-L$libDirArg",
    "-o",
    $elfPath
)
$linkArgs += "-Wl,--start-group"
$linkArgs += $libs
$linkArgs += @("-lc", "-lgcc", "-lm", "-Wl,--end-group")

& $gcc @linkArgs
if ($LASTEXITCODE -ne 0) {
    throw "Link failed for raw-copy static-regions diagnostic app"
}

if (Test-Path $size) {
    & $size $elfPath
}

Write-Host "Built raw-copy static-regions diagnostic app ELF:"
Write-Host $elfPath
Write-Host "Dedicated raw-copy BSP root:"
Write-Host $PlatformSwDir
Write-Host "Dedicated raw-copy toolchain root:"
Write-Host $toolchainRoot
