[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\Xilinx\Vitis\2023.1",
    [ValidateSet("read_only", "write_ctrl", "write_key_1c", "write_key_18", "write_key_14", "write_key_10")]
    [string]$TestCase = "read_only"
)

$ErrorActionPreference = "Stop"

function Get-TestCaseId {
    param([string]$Name)

    switch ($Name) {
        "read_only" { return 1 }
        "write_key_10" { return 2 }
        "write_key_14" { return 3 }
        "write_key_18" { return 4 }
        "write_key_1c" { return 5 }
        "write_ctrl" { return 6 }
        default { throw "Unsupported test case: $Name" }
    }
}

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Join-Path $workspace "vitis_2023_udp_gateway_ws_2\ax7020_udp_gateway_app"
$srcDir = Join-Path $appRoot "src"
$buildRoot = Join-Path $appRoot "SmokeBuild\$TestCase"
$buildSrcDir = Join-Path $buildRoot "src"
$platformDomainDir = Join-Path $workspace "vitis_2023_udp_gateway_ws_2\ax7020_udp_gateway_platform\export\ax7020_udp_gateway_platform\sw\ax7020_udp_gateway_platform\standalone_domain"
$includeDir = Join-Path $platformDomainDir "bspinclude\include"
$libDir = Join-Path $platformDomainDir "bsplib\lib"
$specFile = Join-Path $appRoot "Debug\Xilinx.spec"
$linkerScript = Join-Path $srcDir "lscript.ld"
$gccBinDir = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin"
$gcc = Join-Path $gccBinDir "arm-none-eabi-gcc.exe"
$size = Join-Path $gccBinDir "arm-none-eabi-size.exe"
$testCaseId = Get-TestCaseId -Name $TestCase
$elfPath = Join-Path $buildRoot "ax7020_udp_gateway_app_smoke.elf"
$sizePath = "$elfPath.size"

foreach ($pathInfo in @(
    @{ Label = "App source directory"; Path = $srcDir },
    @{ Label = "Platform include directory"; Path = $includeDir },
    @{ Label = "Platform library directory"; Path = $libDir },
    @{ Label = "Xilinx.spec"; Path = $specFile },
    @{ Label = "Linker script"; Path = $linkerScript },
    @{ Label = "arm-none-eabi-gcc"; Path = $gcc },
    @{ Label = "arm-none-eabi-size"; Path = $size }
)) {
    if (-not (Test-Path $pathInfo.Path)) {
        throw "$($pathInfo.Label) not found: $($pathInfo.Path)"
    }
}

if (Test-Path $buildRoot) {
    Remove-Item -Recurse -Force $buildRoot
}

New-Item -ItemType Directory -Force -Path $buildSrcDir | Out-Null

$compileCommon = @(
    "-Wall",
    "-O0",
    "-g3",
    "-c",
    "-fmessage-length=0",
    "-mcpu=cortex-a9",
    "-mfpu=vfpv3",
    "-mfloat-abi=hard",
    "-I$includeDir",
    "-DUDP_GATEWAY_DIRECT_MMIO_SMOKE_CASE=$testCaseId"
)

$objects = @()

foreach ($sourceName in @("main.c", "platform.c", "udp_crypto_gateway.c")) {
    $sourcePath = Join-Path $srcDir $sourceName
    $objectPath = Join-Path $buildSrcDir (($sourceName -replace "\.c$", ".o"))
    $args = @($compileCommon + @("-o", $objectPath, $sourcePath))

    & $gcc @args
    if ($LASTEXITCODE -ne 0) {
        throw "Compile failed for $sourceName"
    }

    $objects += $objectPath
}

$linkArgs = @(
    "-mcpu=cortex-a9",
    "-mfpu=vfpv3",
    "-mfloat-abi=hard",
    "-Wl,-build-id=none",
    "-specs=$specFile",
    "-Wl,-T",
    "-Wl,$linkerScript",
    "-L$libDir",
    "-o",
    $elfPath
) + $objects + @(
    "-Wl,--start-group,-lxil,-llwip4,-lgcc,-lc,--end-group"
)

& $gcc @linkArgs
if ($LASTEXITCODE -ne 0) {
    throw "Link failed for smoke case '$TestCase'"
}

& $size $elfPath | Tee-Object -FilePath $sizePath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Size reporting failed for smoke case '$TestCase'"
}

Write-Host "Built ws2 smoke app:"
Write-Host $elfPath
Write-Host "Test case: $TestCase"
