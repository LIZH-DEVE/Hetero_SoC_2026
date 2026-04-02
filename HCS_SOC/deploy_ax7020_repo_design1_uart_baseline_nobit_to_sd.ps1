[CmdletBinding()]
param(
    [string]$SdDrive = "E:",
    [string]$BackupDir = "D:\FPGAhanjia\Hetero_SoC_2026_3\sdcard_backup_20260325_repo_design1_uart_baseline_nobit"
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

    if ([string]::IsNullOrWhiteSpace($ConfiguredDrive)) {
        throw "SdDrive must not be empty"
    }

    $sdDriveName = $ConfiguredDrive.Trim().TrimEnd('\').TrimEnd(':')
    if ([string]::IsNullOrWhiteSpace($sdDriveName)) {
        throw "SdDrive must include a valid drive name"
    }

    $sdDriveInfo = Get-PSDrive -Name $sdDriveName -ErrorAction Stop
    if ($sdDriveInfo.Provider.Name -ne "FileSystem") {
        throw "SD drive must be a FileSystem drive: $ConfiguredDrive"
    }

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
$releaseDir = Join-Path $workspace "sd_boot\ax7020_repo_design1_uart_baseline_nobit"
$sourceBoot = Join-Path $releaseDir "BOOT.BIN"
$sourceFsbl = Join-Path $releaseDir "fsbl.elf"
$sourceApp = Join-Path $releaseDir "ax7020_repo_design1_uart_baseline_app.elf"
$sourceBootRead = Join-Path $releaseDir "bootgen_read.txt"
$sourceReadme = Join-Path $releaseDir "readme.txt"
$sdDriveRoot = Resolve-SdDriveRoot -ConfiguredDrive $SdDrive
$targetBoot = Join-Path $sdDriveRoot "BOOT.BIN"

Assert-PathType -Path $releaseDir -PathType Container -Label "Repo design1 no-bit release directory"
foreach ($leafPath in @($sourceBoot, $sourceFsbl, $sourceApp, $sourceBootRead, $sourceReadme)) {
    Assert-PathType -Path $leafPath -PathType Leaf -Label "Repo design1 no-bit release artifact"
}

Assert-TextContains -Path $sourceBootRead -RequiredText @("fsbl.elf", "ax7020_repo_design1_uart_baseline_app.elf") -Label "bootgen_read.txt"
Assert-TextContains -Path $sourceReadme -RequiredText @("No-Bit Diagnostic", "REPO DESIGN1 UART BASELINE") -Label "readme.txt"

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

$releaseArtifacts = [ordered]@{
    "BOOT.BIN" = $sourceBoot
    "fsbl.elf" = $sourceFsbl
    "ax7020_repo_design1_uart_baseline_app.elf" = $sourceApp
    "bootgen_read.txt" = $sourceBootRead
    "readme.txt" = $sourceReadme
}

Write-Host "Repo design1 no-bit release manifest:"
foreach ($artifactName in $releaseArtifacts.Keys) {
    $artifactPath = $releaseArtifacts[$artifactName]
    $artifactItem = Get-Item -Path $artifactPath
    $artifactHash = (Get-FileHash -Algorithm SHA256 -Path $artifactPath).Hash
    Write-Host ("  {0}: {1}" -f $artifactName, $artifactPath)
    Write-Host ("    size={0} sha256={1}" -f $artifactItem.Length, $artifactHash)
}

if (Test-Path -Path $targetBoot -PathType Leaf) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupBoot = Join-Path $BackupDir "BOOT_before_repo_design1_uart_baseline_nobit_$timestamp.bin"
    Copy-Item -Path $targetBoot -Destination $backupBoot -Force
    Write-Host "Backed up existing SD BOOT.BIN:"
    Write-Host $backupBoot
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

Write-Host "Deployed repo design1 no-bit BOOT.BIN to SD:"
Write-Host $targetBoot
Write-Host "SHA256: $targetHash"
Write-Host "Expected board-side behavior:"
Write-Host "  - UART should print repo design_1 baseline banner and heartbeat"
Write-Host "  - If this stays silent, the issue is broader than raw-copy and affects repo-generated no-bit boot images."
