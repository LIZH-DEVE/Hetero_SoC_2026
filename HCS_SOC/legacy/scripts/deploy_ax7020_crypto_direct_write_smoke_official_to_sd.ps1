[CmdletBinding()]
param(
    [ValidateSet("read_only", "write_ctrl", "write_key_1c", "write_key_18", "write_key_14", "write_key_10")]
    [string]$TestCase = "read_only",
    [string]$SdDrive = "E:",
    [string]$BackupDir = "D:\FPGAhanjia\Hetero_SoC_2026_3\sdcard_backup_20260321_0045"
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceBoot = Join-Path $workspace "sd_boot\crypto_direct_write_smoke_official\$TestCase\BOOT.BIN"
$targetBoot = Join-Path $SdDrive "BOOT.BIN"

if (-not (Test-Path $sourceBoot)) {
    throw "Official smoke BOOT.BIN not found for test case '$TestCase': $sourceBoot"
}

if (-not (Test-Path $SdDrive)) {
    throw "SD drive is not ready: $SdDrive"
}

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

if (Test-Path $targetBoot) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupBoot = Join-Path $BackupDir "BOOT_from_sd_before_crypto_direct_write_smoke_official_${TestCase}_$timestamp.bin"
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

Write-Host "Deployed official smoke BOOT.BIN to SD:"
Write-Host $targetBoot
Write-Host "Test case: $TestCase"
Write-Host "SHA256: $targetHash"
