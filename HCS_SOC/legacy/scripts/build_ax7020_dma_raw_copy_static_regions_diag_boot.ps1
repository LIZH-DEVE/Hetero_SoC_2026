[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$XsctBat = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat",
    [string]$VitisRoot = "D:\Xilinx\Vitis\2024.1",
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
    [string]$XsaPath = "",
    [string]$WorkspaceRoot = "",
    [string]$PlatformName = "ax7020_dma_raw_copy_platform",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$exportScript = Join-Path $workspace "export_raw_copy_dma_xsa.ps1"
$platformScript = Join-Path $workspace "generate_ax7020_standalone_platform.ps1"
$appBuildScript = Join-Path $workspace "build_ax7020_dma_raw_copy_static_regions_diag_app.ps1"
$templateBif = Join-Path $workspace "sd_boot\ax7020_dma_raw_copy_static_regions_diag\boot.bif"

if ([string]::IsNullOrWhiteSpace($XsaPath)) {
    $XsaPath = Join-Path $workspace "raw_copy_dma_wrapper.xsa"
}
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Join-Path $workspace "ax7020_dma_raw_copy_platform_xsct\workspace"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $workspace "sd_boot\ax7020_dma_raw_copy_static_regions_diag"
}
$appBuildDir = Join-Path $workspace "ax7020_dma_raw_copy_static_regions_diag_app\build"

function Resolve-BootgenExecutable {
    param([string]$ConfiguredPath)

    foreach ($candidate in @($ConfiguredPath, "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat", "C:\Xilinx\Vivado\2024.1\bin\bootgen.bat")) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "bootgen was not found. Pass -BootgenPath explicitly."
}

$requiredInputs = @($exportScript, $platformScript, $appBuildScript, $templateBif, $XsctBat)
foreach ($path in $requiredInputs) {
    if (-not (Test-Path $path)) {
        throw "Required raw-copy static-regions build input not found: $path"
    }
}

$platformSwDir = Join-Path $WorkspaceRoot "standalone_bsp\ps7_cortexa9_0"
$fsblElf = Join-Path $WorkspaceRoot "$PlatformName\zynq_fsbl\fsbl.elf"
$needFreshPlatform = @(
    -not (Test-Path $XsaPath),
    -not (Test-Path (Join-Path $platformSwDir "include\xparameters.h")),
    -not (Test-Path $fsblElf)
) -contains $true

if ($needFreshPlatform) {
    & $exportScript -VivadoBat $VivadoBat -XsaPath $XsaPath
    if ($LASTEXITCODE -ne 0) {
        throw "Fresh raw-copy XSA export failed"
    }
    if (-not (Test-Path $XsaPath)) {
        throw "Fresh raw-copy XSA not found after export: $XsaPath"
    }

    & $platformScript -XsctBat $XsctBat -XsaPath $XsaPath -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
    if ($LASTEXITCODE -ne 0) {
        throw "Dedicated raw-copy platform generation failed"
    }
}
else {
    Write-Host "Reusing existing dedicated raw-copy XSA/platform workspace:"
    Write-Host $XsaPath
    Write-Host $WorkspaceRoot
}

if (-not (Test-Path (Join-Path $platformSwDir "include\xparameters.h"))) {
    throw "Dedicated raw-copy standalone BSP root not found: $platformSwDir"
}

if (-not (Test-Path $fsblElf)) {
    throw "Fresh raw-copy fsbl.elf not found: $fsblElf"
}

$xsaExtractDir = Join-Path $OutputDir "xsa_extract"
if (Test-Path $xsaExtractDir) {
    Remove-Item -Recurse -Force $xsaExtractDir
}
New-Item -ItemType Directory -Force -Path $xsaExtractDir | Out-Null
tar -xf $XsaPath -C $xsaExtractDir
if ($LASTEXITCODE -ne 0) {
    throw "Failed to extract raw-copy XSA: $XsaPath"
}

$bitstream = Get-ChildItem -Path $xsaExtractDir -File -Filter *.bit |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $bitstream) {
    throw "No bitstream found inside raw-copy XSA: $XsaPath"
}

& $appBuildScript -VitisRoot $VitisRoot -PlatformSwDir $platformSwDir -OutputDir $appBuildDir
if ($LASTEXITCODE -ne 0) {
    throw "Raw-copy static-regions diagnostic app build failed"
}

$appElf = Join-Path $appBuildDir "ax7020_dma_raw_copy_static_regions_diag_app.elf"
foreach ($path in @($fsblElf, $bitstream.FullName, $appElf)) {
    if (-not (Test-Path $path)) {
        throw "Required raw-copy static-regions boot artifact not found: $path"
    }
}

$bootgen = Resolve-BootgenExecutable -ConfiguredPath $BootgenPath
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$stagedFsbl = Join-Path $OutputDir "fsbl.elf"
$stagedBit = Join-Path $OutputDir "dma_raw_copy_static_regions_diag.bit"
$stagedApp = Join-Path $OutputDir "ax7020_dma_raw_copy_static_regions_diag_app.elf"
$bootBin = Join-Path $OutputDir "BOOT.BIN"
$bootRead = Join-Path $OutputDir "bootgen_read.txt"
$readme = Join-Path $OutputDir "readme.txt"

Copy-Item -Path $fsblElf -Destination $stagedFsbl -Force
Copy-Item -Path $bitstream.FullName -Destination $stagedBit -Force
Copy-Item -Path $appElf -Destination $stagedApp -Force

Push-Location $OutputDir
try {
    & $bootgen -image $templateBif -arch zynq -o $bootBin -w
    if ($LASTEXITCODE -ne 0) {
        throw "bootgen failed for raw-copy static-regions diagnostic BOOT.BIN"
    }

    $readback = & $bootgen -read $bootBin 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "bootgen -read failed for raw-copy static-regions diagnostic BOOT.BIN"
    }
    Set-Content -Path $bootRead -Value $readback -Encoding ASCII
}
finally {
    Pop-Location
}

$bootHash = (Get-FileHash -Path $bootBin -Algorithm SHA256).Hash
$readmeText = @"
AX7020 raw-copy static-regions diagnostic image

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from raw_copy_dma_wrapper.xsa
2. fresh raw-copy bitstream extracted from that same XSA
3. raw-copy static-regions diagnostic app ELF built against dedicated raw-copy standalone BSP

Expected board-side behavior:
- UART prints:
  RAWCOPY STATIC REGIONS DIAG
  RAWCOPY_STATIC_REGIONS_OK
  RAWCOPY_STATIC_HEARTBEAT ...
"@
Set-Content -Path $readme -Value $readmeText -Encoding ASCII

Write-Host "Generated raw-copy static-regions diagnostic BOOT.BIN:"
Write-Host $bootBin
Write-Host "SHA256: $bootHash"
Write-Host "bootgen -read: $bootRead"
