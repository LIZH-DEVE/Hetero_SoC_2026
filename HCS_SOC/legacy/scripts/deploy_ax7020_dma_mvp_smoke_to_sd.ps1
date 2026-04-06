[CmdletBinding()]
param(
    [string]$SdDrive = "E:",
    [string]$BackupDir = "D:\FPGAhanjia\Hetero_SoC_2026_3\sdcard_backup_20260324_dma_smoke"
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$timingParserScript = Join-Path $workspace "read_vivado_timing_summary.ps1"
$timingSummaryReport = Join-Path $workspace "timing_triage\system_wrapper_current\timing_summary.rpt"
$sourceBoot = Join-Path $workspace "sd_boot\ax7020_dma_mvp_smoke_system\BOOT.BIN"

if (-not (Test-Path $timingParserScript)) {
    throw "Timing parser script not found: $timingParserScript"
}

& powershell -ExecutionPolicy Bypass -File $timingParserScript `
    -ReportPath $timingSummaryReport `
    -FailIfViolating
if ($LASTEXITCODE -ne 0) {
    throw "Refusing DMA smoke deploy because system_wrapper timing is not clean"
}

$targetBoot = Join-Path $SdDrive "BOOT.BIN"

if (-not (Test-Path $sourceBoot)) {
    throw "DMA smoke BOOT.BIN not found: $sourceBoot"
}

if (-not (Test-Path $SdDrive)) {
    throw "SD drive is not ready: $SdDrive"
}

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

if (Test-Path $targetBoot) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupBoot = Join-Path $BackupDir "BOOT_from_sd_before_dma_mvp_smoke_$timestamp.bin"
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

Write-Host "Deployed DMA MVP smoke BOOT.BIN to SD:"
Write-Host $targetBoot
Write-Host "SHA256: $targetHash"
