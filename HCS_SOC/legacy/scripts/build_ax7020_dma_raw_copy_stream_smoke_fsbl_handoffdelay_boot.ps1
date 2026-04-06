[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\Xilinx\Vitis\2024.1",
    [string]$XsctBat = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat",
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
    [string]$XsaPath = "",
    [string]$WorkspaceRoot = "",
    [string]$PlatformName = "ax7020_dma_stream_smoke_platform",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Dedicated stream-smoke FSBL handoffdelay release contract:
# - boot image is fixed to [bootloader] fsbl.elf + stream_smoke_dma_wrapper.bit + ax7020_dma_raw_copy_stream_smoke_app.elf
# - variant is handoffdelay
# - bootgen -read must remain part of the release generation flow

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$commonScript = Join-Path $workspace "build_ax7020_dma_raw_copy_stream_smoke_fsbl_diag_boot_common.ps1"
if (-not (Test-Path $commonScript)) {
    throw "Common FSBL diagnostic builder not found: $commonScript"
}

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Join-Path $workspace "ax7020_dma_stream_smoke_fsbl_handoffdelay_xsct\workspace"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $workspace "sd_boot\ax7020_dma_raw_copy_stream_smoke_fsbl_handoffdelay"
}

$invokeArgs = @{
    Variant       = "handoffdelay"
    VitisRoot     = $VitisRoot
    XsctBat       = $XsctBat
    BootgenPath   = $BootgenPath
    WorkspaceRoot = $WorkspaceRoot
    PlatformName  = $PlatformName
    OutputDir     = $OutputDir
}

if (-not [string]::IsNullOrWhiteSpace($XsaPath)) {
    $invokeArgs["XsaPath"] = $XsaPath
}

& $commonScript @invokeArgs
