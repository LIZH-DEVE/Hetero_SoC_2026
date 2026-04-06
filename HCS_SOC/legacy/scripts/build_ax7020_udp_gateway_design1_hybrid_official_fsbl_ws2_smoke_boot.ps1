[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\Xilinx\Vitis\2023.1",
    [ValidateSet("read_only", "write_ctrl", "write_key_1c", "write_key_18", "write_key_14", "write_key_10")]
    [string]$TestCase = "read_only",
    [string]$BootgenPath
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildAppScript = Join-Path $workspace "build_ax7020_udp_gateway_ws2_smoke_app.ps1"
$buildBootScript = Join-Path $workspace "build_boot_bin.ps1"
$appElf = Join-Path $workspace "vitis_2023_udp_gateway_ws_2\ax7020_udp_gateway_app\SmokeBuild\$TestCase\ax7020_udp_gateway_app_smoke.elf"
$outputDir = Join-Path $workspace "sd_boot\ax7020_udp_gateway_design1_hybrid_official_fsbl_ws2_smoke\$TestCase"
$fsblElf = "D:\FPGAhanjia\Hetero_SoC_2026_3\AX7020_2023.1\course_s2_vitis\06_net_test\Vitis\design_1_wrapper\zynq_fsbl\fsbl.elf"
$bitstream = Join-Path $workspace "platform\export\platform\hw\design_1_wrapper.bit"

foreach ($path in @($buildAppScript, $buildBootScript, $fsblElf, $bitstream)) {
    if (-not (Test-Path $path)) {
        throw "Required path not found: $path"
    }
}

& $buildAppScript -VitisRoot $VitisRoot -TestCase $TestCase
if ($LASTEXITCODE -ne 0) {
    throw "ws2 smoke app build failed."
}

if (-not (Test-Path $appElf)) {
    throw "ws2 smoke app ELF not found: $appElf"
}

& $buildBootScript `
    -BootgenPath $BootgenPath `
    -FsblElf $fsblElf `
    -Bitstream $bitstream `
    -AppElf $appElf `
    -OutputDir $outputDir

if ($LASTEXITCODE -ne 0) {
    throw "Failed to package ws2 smoke BOOT.BIN."
}

$bootBin = Join-Path $outputDir "BOOT.BIN"
$hash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash

Write-Host "ws2 smoke boot image ready:"
Write-Host $bootBin
Write-Host "Test case: $TestCase"
Write-Host "SHA256: $hash"
