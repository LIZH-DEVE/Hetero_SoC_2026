param(
    [string]$Drive = "E:"
)

$ErrorActionPreference = "Stop"

$repoRoot = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026"
$imageDir = Join-Path $repoRoot "HCS_SOC\sd_boot\ax7020_udp_gateway_hybrid_vitis2023_official_fsbl_bit"
$sourceBoot = Join-Path $imageDir "BOOT.BIN"
$destBoot = Join-Path $Drive "BOOT.BIN"
$backupRoot = "D:\FPGAhanjia\Hetero_SoC_2026_3\sdcard_backup_20260321_0045"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupBoot = Join-Path $backupRoot ("BOOT_from_sd_before_hybrid_vitis2023_official_fsbl_bit_{0}.bin" -f $timestamp)

if (-not (Test-Path $sourceBoot)) {
    throw "Missing source BOOT.BIN: $sourceBoot"
}

if (-not (Test-Path $Drive)) {
    throw "SD card drive is not ready: $Drive"
}

if (Test-Path $destBoot) {
    Copy-Item $destBoot $backupBoot -Force
    Write-Host "Backed up existing SD BOOT.BIN to: $backupBoot"
}

Copy-Item $sourceBoot $destBoot -Force
Write-Host "Deployed hybrid BOOT.BIN to: $destBoot"

$srcHash = (Get-FileHash $sourceBoot -Algorithm SHA256).Hash
$dstHash = (Get-FileHash $destBoot -Algorithm SHA256).Hash

Write-Host "Source SHA256: $srcHash"
Write-Host "Target SHA256: $dstHash"

if ($srcHash -ne $dstHash) {
    throw "SHA256 mismatch after SD deployment"
}

Write-Host "Deployment verification passed"
