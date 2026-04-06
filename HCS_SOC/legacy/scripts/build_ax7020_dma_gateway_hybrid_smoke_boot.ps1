[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$VitisRoot = "D:\Xilinx\Vitis\2024.1",
    [string]$XsctBat = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat",
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
    [string]$XsaPath = "",
    [string]$WorkspaceRoot = "",
    [string]$PlatformName = "ax7020_dma_gateway_hybrid_platform",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$exportXsaScript = Join-Path $workspace "export_dma_gateway_hybrid_xsa.ps1"
$platformScript = Join-Path $workspace "generate_ax7020_standalone_platform.ps1"
$appBuildScript = Join-Path $workspace "build_ax7020_dma_gateway_hybrid_smoke_app.ps1"
$bootBuildScript = Join-Path $workspace "build_boot_bin.ps1"
$releaseDir = Join-Path $workspace "sd_boot\ax7020_dma_gateway_hybrid_smoke"
$readmeTemplate = Join-Path $releaseDir "readme.txt"
$appElf = Join-Path $workspace "ax7020_dma_gateway_hybrid_smoke_app\build\ax7020_dma_gateway_hybrid_smoke_app.elf"

if ([string]::IsNullOrWhiteSpace($XsaPath)) {
    $XsaPath = Join-Path $workspace "dma_gateway_hybrid_wrapper.xsa"
}
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Join-Path $workspace "ax7020_dma_gateway_hybrid_platform_xsct\workspace"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = $releaseDir
}

function Resolve-HybridApiBspRoot {
    param(
        [string]$WorkspaceRoot,
        [string]$PlatformName
    )

    $candidates = @(
        (Join-Path $WorkspaceRoot "$PlatformName\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0"),
        (Join-Path $WorkspaceRoot "standalone_bsp\ps7_cortexa9_0")
    )

    foreach ($candidate in $candidates) {
        if ((Test-Path $candidate) -and (Test-Path (Join-Path $candidate "include\xparameters.h"))) {
            return $candidate
        }
    }

    throw "Hybrid platform API BSP root not found under $WorkspaceRoot"
}

function Resolve-HybridFsblElf {
    param(
        [string]$WorkspaceRoot,
        [string]$PlatformName
    )

    $candidates = @(
        (Join-Path $WorkspaceRoot "$PlatformName\zynq_fsbl\fsbl.elf"),
        (Join-Path $WorkspaceRoot "$PlatformName\export\$PlatformName\sw\$PlatformName\boot\fsbl.elf")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Get-Item $candidate)
        }
    }

    return Get-ChildItem -Path $WorkspaceRoot -Recurse -File -Filter fsbl.elf -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

foreach ($requiredPath in @($exportXsaScript, $platformScript, $appBuildScript, $bootBuildScript, $readmeTemplate)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required hybrid release input not found: $requiredPath"
    }
}

& $exportXsaScript -VivadoBat $VivadoBat -XsaPath $XsaPath
if ($LASTEXITCODE -ne 0) {
    throw "Hybrid XSA export failed"
}

& $platformScript -XsctBat $XsctBat -XsaPath $XsaPath -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
if ($LASTEXITCODE -ne 0) {
    throw "Hybrid standalone platform generation failed"
}

$platformSwDir = Resolve-HybridApiBspRoot -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
& $appBuildScript -VitisRoot $VitisRoot -PlatformSwDir $platformSwDir
if ($LASTEXITCODE -ne 0) {
    throw "Hybrid smoke app build failed"
}

if (-not (Test-Path $appElf)) {
    throw "Hybrid smoke app ELF not found: $appElf"
}

$fsblElf = Resolve-HybridFsblElf -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
if ($null -eq $fsblElf) {
    throw "Fresh hybrid fsbl.elf not found under $WorkspaceRoot"
}

$xsaExtractDir = Join-Path $workspace "dma_gateway_hybrid_xsa_extract"
if (Test-Path $xsaExtractDir) {
    Remove-Item -Recurse -Force $xsaExtractDir
}
New-Item -ItemType Directory -Force -Path $xsaExtractDir | Out-Null

tar -xf $XsaPath -C $xsaExtractDir
if ($LASTEXITCODE -ne 0) {
    throw "Failed to extract hybrid XSA: $XsaPath"
}

$bitstream = Get-ChildItem -Path $xsaExtractDir -File -Filter *.bit |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $bitstream) {
    throw "No bitstream found inside hybrid XSA: $XsaPath"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$stagedFsbl = Join-Path $OutputDir "fsbl.elf"
$stagedBit = Join-Path $OutputDir "dma_gateway_hybrid_wrapper.bit"
$stagedApp = Join-Path $OutputDir "ax7020_dma_gateway_hybrid_smoke_app.elf"

Copy-Item -Path $fsblElf.FullName -Destination $stagedFsbl -Force
Copy-Item -Path $bitstream.FullName -Destination $stagedBit -Force
Copy-Item -Path $appElf -Destination $stagedApp -Force

$templateReleaseDir = Split-Path -Parent $readmeTemplate
$resolvedOutputDir = (Resolve-Path $OutputDir).Path
$resolvedTemplateDir = (Resolve-Path $templateReleaseDir).Path
if ($resolvedOutputDir -ne $resolvedTemplateDir) {
    Copy-Item -Path $readmeTemplate -Destination (Join-Path $OutputDir "readme.txt") -Force
}

& $bootBuildScript `
    -BootgenPath $BootgenPath `
    -FsblElf $stagedFsbl `
    -Bitstream $stagedBit `
    -AppElf $stagedApp `
    -OutputDir $OutputDir

if ($LASTEXITCODE -ne 0) {
    throw "Failed to package hybrid smoke BOOT.BIN"
}

$bootBin = Join-Path $OutputDir "BOOT.BIN"
if (-not (Test-Path $bootBin)) {
    throw "Hybrid smoke BOOT.BIN not found after packaging: $bootBin"
}

$bootHash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash

Write-Host "Generated DMA gateway hybrid smoke BOOT.BIN:"
Write-Host $bootBin
Write-Host "Fresh XSA: $XsaPath"
Write-Host "Fresh FSBL: $($fsblElf.FullName)"
Write-Host "Fresh bitstream: $($bitstream.FullName)"
Write-Host "App ELF: $appElf"
Write-Host "SHA256: $bootHash"
Write-Host "3-stage boot structure preserved: fsbl.elf -> dma_gateway_hybrid_wrapper.bit -> ax7020_dma_gateway_hybrid_smoke_app.elf"
