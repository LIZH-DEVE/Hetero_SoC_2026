[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\Xilinx\Vitis\2024.1",
    [Parameter(Mandatory = $true)]
    [string]$PlatformSwDir
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$appSrcDir = Join-Path $workspace "ax7020_repo_design1_uart_baseline_app\src"
$buildDir = Join-Path $workspace "ax7020_repo_design1_uart_baseline_app\build"
$objDir = Join-Path $buildDir "obj"
$includeDir = Join-Path $PlatformSwDir "include"
$libDir = Join-Path $PlatformSwDir "lib"
$specsFile = Join-Path $PlatformSwDir "Xilinx.spec"
$linkerScript = Join-Path $workspace "ax7020_system_uart_smoke_app\src\lscript.ld"
$gcc = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe"
$size = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-size.exe"
$mainSource = Join-Path $appSrcDir "main.c"

foreach ($path in @(
    $appSrcDir,
    $PlatformSwDir,
    $includeDir,
    $libDir,
    $specsFile,
    $linkerScript,
    $gcc,
    $mainSource
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
    "-specs=$specsFile",
    "-ffunction-sections",
    "-fdata-sections",
    "-Wall",
    "-Wextra",
    "-U__clang__",
    "-I$includeDir"
)

$mainObj = Join-Path $objDir "main.o"
$elfPath = Join-Path $buildDir "ax7020_repo_design1_uart_baseline_app.elf"
$mapPath = Join-Path $buildDir "ax7020_repo_design1_uart_baseline_app.map"

& $gcc @commonArgs -c $mainSource -o $mainObj
if ($LASTEXITCODE -ne 0) {
    throw "Compile failed for repo design_1 UART baseline main.c"
}

$linkArgs = @(
    "-O2",
    "-mcpu=cortex-a9",
    "-mfpu=vfpv3",
    "-mfloat-abi=hard",
    "-specs=$specsFile",
    $mainObj,
    "-Wl,-T,$linkerScript",
    "-Wl,-Map,$mapPath",
    "-Wl,--gc-sections",
    "-L$libDir",
    "-Wl,--start-group",
    "-lxilstandalone",
    "-lxiltimer",
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
    throw "Link failed for repo design_1 UART baseline app"
}

if (Test-Path $size) {
    & $size $elfPath
}

Write-Host "Built repo design_1 UART baseline app ELF:"
Write-Host $elfPath
