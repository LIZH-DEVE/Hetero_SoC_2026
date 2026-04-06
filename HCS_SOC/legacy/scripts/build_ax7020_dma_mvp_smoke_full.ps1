[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$XsctBat = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat",
    [string]$VitisRoot = "D:\Xilinx\Vitis\2024.1",
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
    [ValidateRange(1,8)]
    [int]$CryptoInstances = 2
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$freshBuildScript = Join-Path $workspace "build_ax7020_dma_mvp_smoke_fresh.ps1"

foreach ($path in @($freshBuildScript)) {
    if (-not (Test-Path $path)) {
        throw "Required script not found: $path"
    }
}

& powershell -ExecutionPolicy Bypass -File $freshBuildScript `
    -VivadoBat $VivadoBat `
    -XsctBat $XsctBat `
    -VitisRoot $VitisRoot `
    -BootgenPath $BootgenPath `
    -CryptoInstances $CryptoInstances
if ($LASTEXITCODE -ne 0) {
    throw "Fresh DMA smoke full build failed"
}

Write-Host "AX7020 DMA MVP smoke full build completed through the fresh XSA/FSBL path."
Write-Host (Join-Path $workspace "sd_boot\ax7020_dma_mvp_smoke_system\BOOT.BIN")
