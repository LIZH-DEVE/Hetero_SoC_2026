[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$XsctBat = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat",
    [string]$VitisRoot = "D:\Xilinx\Vitis\2023.1",
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
    [ValidateRange(1,8)]
    [int]$CryptoInstances = 2
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$rebuildScript = Join-Path $workspace "rebuild_system_stage1.ps1"
$syncScript = Join-Path $workspace "sync_system_wrapper_platform.ps1"
$bootScript = Join-Path $workspace "build_ax7020_dma_mvp_smoke_boot.ps1"
$xsaPath = Join-Path $workspace "system_wrapper.xsa"
$bitPath = Join-Path $workspace "HCS_SOC.runs\impl_1\system_wrapper.bit"

foreach ($path in @($rebuildScript, $syncScript, $bootScript)) {
    if (-not (Test-Path $path)) {
        throw "Required script not found: $path"
    }
}

& powershell -ExecutionPolicy Bypass -File $rebuildScript `
    -VivadoBat $VivadoBat `
    -CryptoInstances $CryptoInstances
if ($LASTEXITCODE -ne 0) {
    throw "Vivado rebuild failed"
}

& powershell -ExecutionPolicy Bypass -File $syncScript `
    -XsctBat $XsctBat `
    -XsaPath $xsaPath `
    -BitPath $bitPath
if ($LASTEXITCODE -ne 0) {
    throw "Platform sync failed"
}

& powershell -ExecutionPolicy Bypass -File $bootScript `
    -VitisRoot $VitisRoot `
    -BootgenPath $BootgenPath
if ($LASTEXITCODE -ne 0) {
    throw "DMA smoke BOOT build failed"
}

Write-Host "AX7020 DMA MVP smoke full build completed."
Write-Host "BOOT directory:"
Write-Host (Join-Path $workspace "sd_boot\ax7020_dma_mvp_smoke_system")
