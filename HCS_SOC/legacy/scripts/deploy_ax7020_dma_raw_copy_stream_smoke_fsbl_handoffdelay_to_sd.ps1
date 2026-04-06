[CmdletBinding()]
param(
    [string]$SdDrive = "E:",
    [string]$BackupDir = "D:\FPGAhanjia\Hetero_SoC_2026_3\sdcard_backup_20260327_dma_stream_smoke_fsbl_handoffdelay"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$commonScript = Join-Path $workspace "deploy_ax7020_dma_raw_copy_stream_smoke_fsbl_diag_to_sd_common.ps1"
if (-not (Test-Path $commonScript)) {
    throw "Common FSBL diagnostic deploy script not found: $commonScript"
}

& $commonScript -Variant handoffdelay -SdDrive $SdDrive -BackupDir $BackupDir
