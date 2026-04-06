$ErrorActionPreference = 'Stop'

$source = 'D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_udp_gateway_vitis2023_custom_fsbl_custom_bit\BOOT.BIN'
$target = 'E:\BOOT.BIN'

if (-not (Test-Path $source)) {
    throw "Source BOOT.BIN not found: $source"
}

if (-not (Test-Path 'E:\')) {
    throw 'SD card drive E: is not available.'
}

$backupRoot = 'D:\FPGAhanjia\Hetero_SoC_2026_3\sdcard_backup_20260321_0045'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backup = Join-Path $backupRoot "BOOT_before_ax7020_udp_gateway_vitis2023_custom_fsbl_custom_bit_$timestamp.BIN"

if (Test-Path $target) {
    Copy-Item $target $backup -Force
    Write-Host "Backed up existing BOOT.BIN to $backup"
}

Copy-Item $source $target -Force

$srcHash = (Get-FileHash $source -Algorithm SHA256).Hash
$dstHash = (Get-FileHash $target -Algorithm SHA256).Hash

Write-Host "Source SHA256: $srcHash"
Write-Host "Target SHA256: $dstHash"

if ($srcHash -ne $dstHash) {
    throw 'Deployment failed: target hash does not match source hash.'
}

Write-Host 'Deployment complete.'
