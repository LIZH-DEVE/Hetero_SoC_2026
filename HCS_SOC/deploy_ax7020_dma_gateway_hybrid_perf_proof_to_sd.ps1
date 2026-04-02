[CmdletBinding()]
param(
    [string]$SdDrive = "E:",
    [string]$BackupDir = "D:\FPGAhanjia\Hetero_SoC_2026_3\sdcard_backup_dma_gateway_hybrid_perf_proof"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$releaseDir = Join-Path $workspace "sd_boot\ax7020_dma_gateway_hybrid_perf_proof"
$sourceBoot = Join-Path $releaseDir "BOOT.BIN"
$sourceBif = Join-Path $releaseDir "boot.bif"
$sourceReadme = Join-Path $releaseDir "readme.txt"

$sdDriveName = $SdDrive.Trim().TrimEnd('\').TrimEnd(':')
$sdDriveRoot = (Get-PSDrive -Name $sdDriveName -ErrorAction Stop).Root
$targetBoot = Join-Path $sdDriveRoot "BOOT.BIN"

foreach ($path in @($releaseDir, $sourceBoot, $sourceBif, $sourceReadme)) {
    if (-not (Test-Path $path)) {
        throw "Hybrid perf proof release artifact missing: $path"
    }
}

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

if (Test-Path $targetBoot) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $BackupDir "BOOT_before_dma_gateway_hybrid_perf_proof_$timestamp.bin"
    Copy-Item -Path $targetBoot -Destination $backupPath -Force
    Write-Host "Backed up existing SD BOOT.BIN:"
    Write-Host $backupPath
}

Copy-Item -Path $sourceBoot -Destination $targetBoot -Force
$targetHash = (Get-FileHash -Algorithm SHA256 -Path $targetBoot).Hash

Write-Host "Deployed DMA gateway hybrid perf proof BOOT.BIN to SD:"
Write-Host $targetBoot
Write-Host "SHA256: $targetHash"
