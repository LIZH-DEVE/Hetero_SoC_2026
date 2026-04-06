[CmdletBinding()]
param(
    [string]$SdDrive = "E:",
    [string]$BackupDir = "D:\FPGAhanjia\Hetero_SoC_2026_3\sdcard_backup_20260326_dma_raw_copy_invalidate_compare_diag"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-Leaf {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "$Label not found: $Path"
    }
}

function Resolve-SdDriveRoot {
    param([string]$ConfiguredDrive)

    $driveName = $ConfiguredDrive.Trim().TrimEnd('\').TrimEnd(':')
    if ([string]::IsNullOrWhiteSpace($driveName)) {
        throw "SdDrive must include a valid drive name"
    }

    $drive = Get-PSDrive -Name $driveName -ErrorAction Stop
    if ($drive.Provider.Name -ne "FileSystem") {
        throw "SD drive must be a FileSystem drive: $ConfiguredDrive"
    }
    if (-not (Test-Path -Path $drive.Root -PathType Container)) {
        throw "SD drive root is not ready: $($drive.Root)"
    }
    return $drive.Root
}

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$releaseDir = Join-Path $workspace "sd_boot\ax7020_dma_raw_copy_invalidate_compare_diag"
$sourceBoot = Join-Path $releaseDir "BOOT.BIN"
$sourceFsbl = Join-Path $releaseDir "fsbl.elf"
$sourceBit = Join-Path $releaseDir "dma_raw_copy_invalidate_compare_diag.bit"
$sourceApp = Join-Path $releaseDir "ax7020_dma_raw_copy_invalidate_compare_diag_app.elf"
$sourceBootRead = Join-Path $releaseDir "bootgen_read.txt"
$sourceReadme = Join-Path $releaseDir "readme.txt"

foreach ($path in @($sourceBoot, $sourceFsbl, $sourceBit, $sourceApp, $sourceBootRead, $sourceReadme)) {
    Assert-Leaf -Path $path -Label "raw-copy invalidate/compare release artifact"
}

$bootReadText = Get-Content -Path $sourceBootRead -Raw -Encoding ASCII
foreach ($required in @("fsbl.elf", "dma_raw_copy_invalidate_compare_diag.bit", "ax7020_dma_raw_copy_invalidate_compare_diag_app.elf")) {
    if ($bootReadText -notlike "*$required*") {
        throw "bootgen_read.txt missing required partition '$required': $sourceBootRead"
    }
}

$sdRoot = Resolve-SdDriveRoot -ConfiguredDrive $SdDrive
$targetBoot = Join-Path $sdRoot "BOOT.BIN"

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
if (Test-Path -Path $targetBoot -PathType Leaf) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupBoot = Join-Path $BackupDir "BOOT_before_dma_raw_copy_invalidate_compare_diag_$timestamp.bin"
    Copy-Item -Path $targetBoot -Destination $backupBoot -Force
    Write-Host "Backed up existing SD BOOT.BIN:"
    Write-Host $backupBoot
}

$sourceItem = Get-Item -Path $sourceBoot
$sourceHash = (Get-FileHash -Path $sourceBoot -Algorithm SHA256).Hash
Copy-Item -Path $sourceBoot -Destination $targetBoot -Force
$targetItem = Get-Item -Path $targetBoot
$targetHash = (Get-FileHash -Path $targetBoot -Algorithm SHA256).Hash

if ($sourceItem.Length -ne $targetItem.Length) {
    throw "BOOT.BIN size mismatch after deploy. Source=$($sourceItem.Length) Target=$($targetItem.Length)"
}
if ($sourceHash -ne $targetHash) {
    throw "BOOT.BIN SHA256 mismatch after deploy. Source=$sourceHash Target=$targetHash"
}

Write-Host "Raw-copy invalidate/compare release manifest:"
foreach ($artifact in @($sourceBoot, $sourceFsbl, $sourceBit, $sourceApp, $sourceBootRead, $sourceReadme)) {
    $item = Get-Item -Path $artifact
    $hash = (Get-FileHash -Path $artifact -Algorithm SHA256).Hash
    Write-Host ("  {0}" -f $artifact)
    Write-Host ("    size={0} sha256={1}" -f $item.Length, $hash)
}

Write-Host "Deployed raw-copy invalidate/compare diagnostic BOOT.BIN to SD:"
Write-Host $targetBoot
Write-Host "SHA256: $targetHash"
