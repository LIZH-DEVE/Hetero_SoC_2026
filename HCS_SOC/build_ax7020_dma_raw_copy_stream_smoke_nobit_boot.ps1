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

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$platformScript = Join-Path $workspace "generate_ax7020_standalone_platform.ps1"
$appBuildScript = Join-Path $workspace "build_ax7020_dma_raw_copy_stream_smoke_app.ps1"
$templateBif = Join-Path $workspace "sd_boot\ax7020_dma_raw_copy_stream_smoke_nobit\boot.bif"
$appElf = Join-Path $workspace "ax7020_dma_raw_copy_stream_smoke_app\build\ax7020_dma_raw_copy_stream_smoke_app.elf"

if ([string]::IsNullOrWhiteSpace($XsaPath)) {
    $XsaPath = Join-Path $workspace "stream_smoke_dma_wrapper.xsa"
}
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Join-Path $workspace "ax7020_dma_stream_smoke_platform_xsct\workspace"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $workspace "sd_boot\ax7020_dma_raw_copy_stream_smoke_nobit"
}

function Resolve-StreamSmokeApiBspRoot {
    param([string]$WorkspaceRoot)

    $candidates = @(
        (Join-Path $WorkspaceRoot "ax7020_dma_stream_smoke_platform\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0"),
        (Join-Path $WorkspaceRoot "standalone_bsp\ps7_cortexa9_0")
    )

    foreach ($candidate in $candidates) {
        if ((Test-Path $candidate) -and (Test-Path (Join-Path $candidate "include\xparameters.h"))) {
            return $candidate
        }
    }

    throw "Fresh stream-smoke API BSP root not found under $WorkspaceRoot"
}

function Resolve-StreamSmokeFsblElf {
    param([string]$WorkspaceRoot, [string]$PlatformName)

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

foreach ($requiredPath in @($platformScript, $appBuildScript, $templateBif, $XsctBat, $XsaPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required stream-smoke no-bit build input not found: $requiredPath"
    }
}

& $platformScript -XsctBat $XsctBat -XsaPath $XsaPath -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
if ($LASTEXITCODE -ne 0) {
    throw "Dedicated stream-smoke platform generation failed for no-bit diagnostic image"
}

$fsblElf = Resolve-StreamSmokeFsblElf -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
if ($null -eq $fsblElf) {
    throw "Fresh stream-smoke fsbl.elf not found under $WorkspaceRoot"
}
$platformSwDir = Resolve-StreamSmokeApiBspRoot -WorkspaceRoot $WorkspaceRoot

& $appBuildScript -VitisRoot $VitisRoot -PlatformSwDir $platformSwDir
if ($LASTEXITCODE -ne 0) {
    throw "Stream-smoke app build failed for no-bit diagnostic image"
}

foreach ($requiredPath in @($appElf, $fsblElf.FullName)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required stream-smoke no-bit artifact not found: $requiredPath"
    }
}

if (-not (Test-Path $BootgenPath)) {
    throw "bootgen not found: $BootgenPath"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
foreach ($staleArtifact in @(
    "BOOT.BIN",
    "fsbl.elf",
    "ax7020_dma_raw_copy_stream_smoke_app.elf",
    "bootgen_read.txt",
    "readme.txt"
)) {
    $stalePath = Join-Path $OutputDir $staleArtifact
    if (Test-Path $stalePath) {
        Remove-Item -Force -LiteralPath $stalePath
    }
}

$stagedFsbl = Join-Path $OutputDir "fsbl.elf"
$stagedApp = Join-Path $OutputDir "ax7020_dma_raw_copy_stream_smoke_app.elf"
$bootBin = Join-Path $OutputDir "BOOT.BIN"
$bootRead = Join-Path $OutputDir "bootgen_read.txt"
$readmePath = Join-Path $OutputDir "readme.txt"

Copy-Item -Path $fsblElf.FullName -Destination $stagedFsbl -Force
Copy-Item -Path $appElf -Destination $stagedApp -Force

Push-Location $OutputDir
try {
    & $BootgenPath -image $templateBif -arch zynq -o $bootBin -w
    if ($LASTEXITCODE -ne 0) {
        throw "bootgen failed for dedicated stream-smoke no-bit BOOT.BIN"
    }

    $readback = & $BootgenPath -read $bootBin 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "bootgen -read failed for dedicated stream-smoke no-bit BOOT.BIN"
    }
    Set-Content -Path $bootRead -Value $readback -Encoding ASCII
}
finally {
    Pop-Location
}

$bootHash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash
$readme = @"
AX7020 Stream Smoke DMA (No-Bit Diagnostic)

Purpose:
- Diagnostic image to separate stream-smoke bitstream/PL failures from FSBL/app bring-up.
- Uses the same fresh stream-smoke FSBL and the same stream-smoke app.
- Omits the PL bitstream on purpose.

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from stream_smoke_dma_wrapper.xsa
2. stream-smoke application ELF

Fresh source chain:
- XSA path: $XsaPath
- XSCT workspace: $WorkspaceRoot
- Platform name: $PlatformName
- FSBL path: $($fsblElf.FullName)
- App API BSP root: $platformSwDir
- App ELF path: $appElf
- SHA256: $bootHash

Expected board-side behavior:
- UART prints at least:
  DMA stream smoke image
"@

Set-Content -Path $readmePath -Value $readme -Encoding ASCII

Write-Host "Generated dedicated stream-smoke no-bit BOOT.BIN:"
Write-Host $bootBin
Write-Host "Fresh XSA: $XsaPath"
Write-Host "Fresh FSBL: $($fsblElf.FullName)"
Write-Host "App ELF: $appElf"
Write-Host "bootgen -read: $bootRead"
Write-Host "SHA256: $bootHash"
