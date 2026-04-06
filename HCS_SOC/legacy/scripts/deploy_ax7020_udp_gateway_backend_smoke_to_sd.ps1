[CmdletBinding()]
param(
    [string]$SdDrive = "E:",
    [string]$BackupDir = "D:\FPGAhanjia\Hetero_SoC_2026_3\sdcard_backup_udp_gateway_backend_smoke"
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

    return $text
}

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$releaseDir = Join-Path $workspace "sd_boot\ax7020_udp_gateway_backend_smoke"
$sourceBoot = Join-Path $releaseDir "BOOT.BIN"
$sourceBif = Join-Path $releaseDir "boot.bif"
$sourceReadme = Join-Path $releaseDir "readme.txt"
$sourceBootgenRead = Join-Path $releaseDir "bootgen_read.txt"
$sourceFsbl = Join-Path $releaseDir "fsbl.elf"
$sourceBit = Join-Path $releaseDir "dma_gateway_hybrid_wrapper.bit"
$sourceApp = Join-Path $releaseDir "ax7020_udp_gateway_backend_smoke_app.elf"
$sdDriveRoot = Resolve-SdDriveRoot -ConfiguredDrive $SdDrive
$targetBoot = Join-Path $sdDriveRoot "BOOT.BIN"

Assert-PathType -Path $releaseDir -PathType Container -Label "UDP gateway backend smoke release directory"
foreach ($leafPath in @($sourceBoot, $sourceBif, $sourceReadme, $sourceBootgenRead, $sourceFsbl, $sourceBit, $sourceApp)) {
    Assert-PathType -Path $leafPath -PathType Leaf -Label "UDP gateway backend smoke release artifact"
}

Assert-TextContains -Path $sourceBif -RequiredText @(
    "fsbl.elf",
    "dma_gateway_hybrid_wrapper.bit",
    "ax7020_udp_gateway_backend_smoke_app.elf"
) -Label "boot.bif" | Out-Null
Assert-TextContains -Path $sourceBootgenRead -RequiredText @(
    "fsbl.elf",
    "dma_gateway_hybrid_wrapper.bit",
    "ax7020_udp_gateway_backend_smoke_app.elf"
) -Label "bootgen_read.txt" | Out-Null
Assert-TextContains -Path $sourceReadme -RequiredText @(
    "UDP gateway backend smoke image",
    "Phase B backend split smoke image",
    "DIRECT_BACKEND PASS",
    "DMA_PROBE EXACT_FIT PASS",
    "DMA_PROBE SHORT PASS",
    "DMA_PROBE OVERFLOW PASS",
    "DMA_PROBE WRONG_PORT PASS",
    "DMA_PROBE UNALIGNED_REJECT PASS",
    "DMA_PROBE PASS",
    "UDP gateway backend smoke PASS"
) -Label "readme.txt" | Out-Null

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

$releaseArtifacts = [ordered]@{
    "BOOT.BIN" = $sourceBoot
    "boot.bif" = $sourceBif
    "bootgen_read.txt" = $sourceBootgenRead
    "readme.txt" = $sourceReadme
}

Write-Host "UDP gateway backend smoke release manifest:"
foreach ($artifactName in $releaseArtifacts.Keys) {
    $artifactPath = $releaseArtifacts[$artifactName]
    $artifactItem = Get-Item -Path $artifactPath
    $artifactHash = (Get-FileHash -Algorithm SHA256 -Path $artifactPath).Hash
    Write-Host ("  {0}: {1}" -f $artifactName, $artifactPath)
    Write-Host ("    size={0} sha256={1}" -f $artifactItem.Length, $artifactHash)
}

if (Test-Path -Path $targetBoot -PathType Leaf) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupBoot = Join-Path $BackupDir "BOOT_before_udp_gateway_backend_smoke_$timestamp.bin"
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

Write-Host "Deployed UDP gateway backend smoke BOOT.BIN to SD:"
Write-Host $targetBoot
Write-Host "SHA256: $targetHash"
