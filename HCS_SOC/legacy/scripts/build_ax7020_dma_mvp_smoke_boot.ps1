[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\Xilinx\Vitis\2023.1",
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat"
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$appBuildScript = Join-Path $workspace "build_ax7020_dma_mvp_smoke_app.ps1"
$bootBuildScript = Join-Path $workspace "build_boot_bin.ps1"
$appElf = Join-Path $workspace "ax7020_dma_mvp_smoke_app\build\ax7020_dma_mvp_smoke_app.elf"
$fsblElf = Join-Path $workspace "platform\export\platform\sw\boot\fsbl.elf"
$bitstream = Join-Path $workspace "platform\export\platform\hw\system_wrapper.bit"
$outputDir = Join-Path $workspace "sd_boot\ax7020_dma_mvp_smoke_system"
$readmePath = Join-Path $outputDir "readme.txt"

foreach ($path in @($appBuildScript, $bootBuildScript)) {
    if (-not (Test-Path $path)) {
        throw "Required script not found: $path"
    }
}

& powershell -ExecutionPolicy Bypass -File $appBuildScript -VitisRoot $VitisRoot
if ($LASTEXITCODE -ne 0) {
    throw "DMA smoke app build failed"
}

& powershell -ExecutionPolicy Bypass -File $bootBuildScript `
    -BootgenPath $BootgenPath `
    -FsblElf $fsblElf `
    -Bitstream $bitstream `
    -AppElf $appElf `
    -OutputDir $outputDir
if ($LASTEXITCODE -ne 0) {
    throw "BOOT.BIN generation failed"
}

$readme = @"
AX7020 DMA MVP Smoke Image

Contents:
- BOOT.BIN = FSBL + system_wrapper.bit + ax7020_dma_mvp_smoke_app.elf

Board-side scope:
1. UART banner and DMA CSR snapshot
2. One normal descriptor via PS CSR injector -> PBM -> Crypto -> DMA -> CSW
3. One error descriptor returning CSW ERR + STS

This image does not include:
- UDP gateway
- control plane ports 4660/4661/4662
- real DNA binding
- strengthened self-destruct
"@

Set-Content -Path $readmePath -Value $readme -Encoding ASCII

Write-Host "Generated DMA smoke BOOT directory:"
Write-Host $outputDir
