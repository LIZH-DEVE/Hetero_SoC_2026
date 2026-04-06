[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\Xilinx\Vitis\2023.1"
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$appSrcDir = Join-Path $workspace "ax7020_system_uart_smoke_app\src"
$buildDir = Join-Path $workspace "ax7020_system_uart_smoke_app\build"
$objDir = Join-Path $buildDir "obj"
$platformSwDir = Join-Path $workspace "platform\export\platform\sw\standalone_ps7_cortexa9_0"
$includeDir = Join-Path $platformSwDir "include"
$libDir = Join-Path $platformSwDir "lib"
$specsFile = Join-Path $platformSwDir "Xilinx.spec"
$linkerScript = Join-Path $appSrcDir "lscript.ld"
$gcc = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe"
$size = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-size.exe"
$mainSource = Join-Path $appSrcDir "main.c"

foreach ($path in @(
    $appSrcDir,
    $platformSwDir,
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
$elfPath = Join-Path $buildDir "ax7020_system_uart_smoke_app.elf"
$mapPath = Join-Path $buildDir "ax7020_system_uart_smoke_app.map"

& $gcc @commonArgs -c $mainSource -o $mainObj
if ($LASTEXITCODE -ne 0) {
    throw "Compile failed for system UART smoke main.c"
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
    throw "Link failed for system UART smoke app"
}

if (Test-Path $size) {
    & $size $elfPath
}

Write-Host "Built system UART smoke app ELF:"
Write-Host $elfPath
