[CmdletBinding()]
param(
    [string]$SdDrive = "E:",
    [string]$BackupDir = "D:\FPGAhanjia\Hetero_SoC_2026_3\sdcard_backup_20260324_vendor_ps_hello"
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceBoot = Join-Path $workspace "sd_boot\ax7020_vendor_ps_hello_baseline\BOOT.BIN"
$targetBoot = Join-Path $SdDrive "BOOT.BIN"

if (-not (Test-Path $sourceBoot)) {
    throw "Vendor ps_hello BOOT.BIN not found: $sourceBoot"
}

if (-not (Test-Path $SdDrive)) {
    throw "SD drive is not ready: $SdDrive"
}

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

if (Test-Path $targetBoot) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupBoot = Join-Path $BackupDir "BOOT_from_sd_before_vendor_ps_hello_$timestamp.bin"
    Copy-Item -Path $targetBoot -Destination $backupBoot -Force
    Write-Host "Backed up existing SD BOOT.BIN:"
    Write-Host $backupBoot
}

$sourceHash = (Get-FileHash -Algorithm SHA256 -Path $sourceBoot).Hash

Copy-Item -Path $sourceBoot -Destination $targetBoot -Force

$targetHash = (Get-FileHash -Algorithm SHA256 -Path $targetBoot).Hash
if ($targetHash -ne $sourceHash) {
    throw "SHA256 mismatch after deploy. Source=$sourceHash Target=$targetHash"
}

Write-Host "Deployed vendor ps_hello baseline BOOT.BIN to SD:"
Write-Host $targetBoot
Write-Host "SHA256: $targetHash"
