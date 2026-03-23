[CmdletBinding()]
param(
    [string]$XsctPath = "D:\Xilinx\Vitis\2023.1\bin\xsct.bat",
    [string]$VitisRoot = "D:\Xilinx\Vitis\2023.1",
    [ValidateSet("read_only", "write_ctrl_safe", "write_key_1c_flip", "write_key_18_flip", "write_key_14_flip", "write_key_10_flip", "aes_block_smoke_enc")]
    [string]$TestCase = "read_only"
)

$ErrorActionPreference = "Stop"

function Get-TestCaseId {
    param([string]$Name)

    switch ($Name) {
        "read_only" { return 1 }
        "write_key_10_flip" { return 2 }
        "write_key_14_flip" { return 3 }
        "write_key_18_flip" { return 4 }
        "write_key_1c_flip" { return 5 }
        "write_ctrl_safe" { return 6 }
        "aes_block_smoke_enc" { return 7 }
        default { throw "Unsupported test case: $Name" }
    }
}

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$ensureWorkspaceScript = Join-Path $workspace "build_ax7020_udp_gateway_backup_xsa.ps1"
$sourceAppDir = Join-Path $workspace "vitis_2023_udp_gateway_ws_2\ax7020_udp_gateway_app\src"
$backupWs = Join-Path $workspace "vitis_2023_udp_gateway_backup_xsa_ws"
$buildRoot = Join-Path $backupWs "SmokeOnlyBuild\$TestCase"
$buildSrcDir = Join-Path $buildRoot "src"
$includeDir = Join-Path $backupWs "ax7020_udp_gateway_backup_platform\zynq_fsbl\zynq_fsbl_bsp\ps7_cortexa9_0\include"
$libDir = Join-Path $backupWs "ax7020_udp_gateway_backup_platform\zynq_fsbl\zynq_fsbl_bsp\ps7_cortexa9_0\lib"
$specFile = Join-Path $backupWs "ax7020_udp_gateway_backup_platform\zynq_fsbl\Xilinx.spec"
$linkerScript = Join-Path $sourceAppDir "lscript.ld"
$gccBinDir = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin"
$gcc = Join-Path $gccBinDir "arm-none-eabi-gcc.exe"
$size = Join-Path $gccBinDir "arm-none-eabi-size.exe"
$testCaseId = Get-TestCaseId -Name $TestCase
$elfPath = Join-Path $buildRoot "ax7020_udp_gateway_backup_smoke.elf"
$sizePath = "$elfPath.size"

if ((-not (Test-Path $includeDir)) -or (-not (Test-Path $libDir)) -or (-not (Test-Path $specFile))) {
    & $ensureWorkspaceScript -XsctPath $XsctPath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create backup-XSA workspace."
    }
}

foreach ($pathInfo in @(
    @{ Label = "ws_2 source directory"; Path = $sourceAppDir },
    @{ Label = "Backup fsbl BSP include directory"; Path = $includeDir },
    @{ Label = "Backup fsbl BSP library directory"; Path = $libDir },
    @{ Label = "Backup fsbl Xilinx.spec"; Path = $specFile },
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
    "-DUDP_GATEWAY_SMOKE_ONLY_BUILD=1",
    "-DUDP_GATEWAY_DIRECT_MMIO_SMOKE_CASE=$testCaseId"
)

$objects = @()

foreach ($sourceName in @("main.c", "udp_crypto_gateway.c")) {
    $sourcePath = Join-Path $sourceAppDir $sourceName
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
    "-Wl,--start-group,-lxil,-lgcc,-lc,--end-group"
)

& $gcc @linkArgs
if ($LASTEXITCODE -ne 0) {
    throw "Link failed for smoke case '$TestCase'"
}

& $size $elfPath | Tee-Object -FilePath $sizePath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Size reporting failed for smoke case '$TestCase'"
}

Write-Host "Built backup-XSA ws2 smoke-only app:"
Write-Host $elfPath
Write-Host "Test case: $TestCase"
