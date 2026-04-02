[CmdletBinding()]
param(
    [string]$SdDrive = "E:",
    [string]$BackupDir = "D:\FPGAhanjia\Hetero_SoC_2026_3\sdcard_backup_20260327_dma_stream_smoke_fsbl_nopostcfg"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-PathType {
    param(
        [string]$Path,
        [ValidateSet("Leaf", "Container")]
        [string]$PathType,
        [string]$Label
    )

    if (-not (Test-Path -Path $Path -PathType $PathType)) {
        throw "$Label not found or wrong type ($PathType): $Path"
    }
}

function Resolve-SdDriveRoot {
    param([string]$ConfiguredDrive)

    $sdDriveName = $ConfiguredDrive.Trim().TrimEnd('\').TrimEnd(':')
    $sdDriveInfo = Get-PSDrive -Name $sdDriveName -ErrorAction Stop
    Assert-PathType -Path $sdDriveInfo.Root -PathType Container -Label "SD drive root"
    return $sdDriveInfo.Root
}

function Assert-TextContains {
    param(
        [string]$Path,
        [string[]]$RequiredText,
        [string]$Label
    )

    $text = Get-Content -Raw -Encoding ASCII -Path $Path
    foreach ($needle in $RequiredText) {
        if ($text -notlike "*$needle*") {
            throw "$Label missing required text '$needle': $Path"
        }
    }
}

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$releaseDir = Join-Path $workspace "sd_boot\ax7020_dma_raw_copy_stream_smoke_fsbl_nopostcfg"
$sourceBoot = Join-Path $releaseDir "BOOT.BIN"
$sourceFsbl = Join-Path $releaseDir "fsbl.elf"
$sourceBit = Join-Path $releaseDir "stream_smoke_dma_wrapper.bit"
$sourceApp = Join-Path $releaseDir "ax7020_dma_raw_copy_stream_smoke_app.elf"
$sourceBootRead = Join-Path $releaseDir "bootgen_read.txt"
$sourceReadme = Join-Path $releaseDir "readme.txt"
$sdDriveRoot = Resolve-SdDriveRoot -ConfiguredDrive $SdDrive
$targetBoot = Join-Path $sdDriveRoot "BOOT.BIN"

Assert-PathType -Path $releaseDir -PathType Container -Label "FSBL no-post-config release directory"
foreach ($leafPath in @($sourceBoot, $sourceFsbl, $sourceBit, $sourceApp, $sourceBootRead, $sourceReadme)) {
    Assert-PathType -Path $leafPath -PathType Leaf -Label "FSBL no-post-config release artifact"
}

Assert-TextContains -Path $sourceBootRead -RequiredText @("fsbl.elf", "stream_smoke_dma_wrapper.bit", "ax7020_dma_raw_copy_stream_smoke_app.elf") -Label "bootgen_read.txt"
Assert-TextContains -Path $sourceReadme -RequiredText @("no-post-config", "temporary board-proven Phase 3 baseline") -Label "readme.txt"

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
if (Test-Path -Path $targetBoot -PathType Leaf) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupBoot = Join-Path $BackupDir "BOOT_before_dma_stream_smoke_fsbl_nopostcfg_$timestamp.bin"
    Copy-Item -Path $targetBoot -Destination $backupBoot -Force
}

$sourceItem = Get-Item -Path $sourceBoot
$sourceHash = (Get-FileHash -Algorithm SHA256 -Path $sourceBoot).Hash
Copy-Item -Path $sourceBoot -Destination $targetBoot -Force
$targetItem = Get-Item -Path $targetBoot
$targetHash = (Get-FileHash -Algorithm SHA256 -Path $targetBoot).Hash

if ($targetItem.Length -ne $sourceItem.Length) {
    throw "BOOT.BIN size mismatch after deploy. Source=$($sourceItem.Length) Target=$($targetItem.Length)"
}
if ($targetHash -ne $sourceHash) {
    throw "SHA256 mismatch after deploy. Source=$sourceHash Target=$targetHash"
}

Write-Host "Deployed dedicated stream-smoke FSBL no-post-config BOOT.BIN to SD:"
Write-Host $targetBoot
Write-Host "SHA256: $targetHash"
