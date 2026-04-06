[CmdletBinding()]
param(
    [string]$XsctPath = "D:\Xilinx\Vitis\2023.1\bin\xsct.bat",
    [string]$VitisRoot = "D:\Xilinx\Vitis\2023.1",
    [ValidateSet("read_only", "write_ctrl_safe", "write_key_1c_flip", "write_key_18_flip", "write_key_14_flip", "write_key_10_flip", "aes_block_smoke_enc")]
    [string]$TestCase = "read_only",
    [string]$BootgenPath
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildAppScript = Join-Path $workspace "build_ax7020_udp_gateway_backup_xsa_ws2_smoke_app.ps1"
$buildBootScript = Join-Path $workspace "build_boot_bin.ps1"
$backupWs = Join-Path $workspace "vitis_2023_udp_gateway_backup_xsa_ws"
$appElf = Join-Path $backupWs "SmokeOnlyBuild\$TestCase\ax7020_udp_gateway_backup_smoke.elf"
$outputDir = Join-Path $workspace "sd_boot\ax7020_udp_gateway_backup_xsa_ws2_smoke\$TestCase"
$fsblElf = Join-Path $backupWs "ax7020_udp_gateway_backup_platform\zynq_fsbl\fsbl.elf"
$bitstream = Join-Path $workspace "..\BACKUP_UART_WORKING_20260315\design_1_wrapper.bit"

foreach ($path in @($buildAppScript, $buildBootScript, $bitstream)) {
    if (-not (Test-Path $path)) {
        throw "Required path not found: $path"
    }
}

& $buildAppScript -XsctPath $XsctPath -VitisRoot $VitisRoot -TestCase $TestCase
if ($LASTEXITCODE -ne 0) {
    throw "Backup-XSA ws2 smoke app build failed."
}

foreach ($path in @($appElf, $fsblElf)) {
    if (-not (Test-Path $path)) {
        throw "Required generated file not found: $path"
    }
}

& $buildBootScript `
    -BootgenPath $BootgenPath `
    -FsblElf $fsblElf `
    -Bitstream $bitstream `
    -AppElf $appElf `
    -OutputDir $outputDir

if ($LASTEXITCODE -ne 0) {
    throw "Failed to package backup-XSA ws2 smoke BOOT.BIN."
}

$bootBin = Join-Path $outputDir "BOOT.BIN"
$hash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash

Write-Host "backup-XSA ws2 smoke boot image ready:"
Write-Host $bootBin
Write-Host "Test case: $TestCase"
Write-Host "SHA256: $hash"
