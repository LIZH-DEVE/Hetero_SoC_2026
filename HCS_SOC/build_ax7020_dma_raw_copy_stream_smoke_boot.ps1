[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
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
$patchScript = Join-Path $workspace "patch_ax7020_stream_smoke_fsbl.ps1"
$appBuildScript = Join-Path $workspace "build_ax7020_dma_raw_copy_stream_smoke_app.ps1"
$templateBif = Join-Path $workspace "sd_boot\ax7020_dma_raw_copy_stream_smoke\boot.bif"
$appElf = Join-Path $workspace "ax7020_dma_raw_copy_stream_smoke_app\build\ax7020_dma_raw_copy_stream_smoke_app.elf"
$timingParserScript = Join-Path $workspace "read_vivado_timing_summary.ps1"

if ([string]::IsNullOrWhiteSpace($XsaPath)) {
    $XsaPath = Join-Path $workspace "stream_smoke_dma_wrapper.xsa"
}
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Join-Path $workspace "ax7020_dma_stream_smoke_platform_xsct\workspace"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $workspace "sd_boot\ax7020_dma_raw_copy_stream_smoke"
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

function Resolve-BootgenExecutable {
    param([string]$ConfiguredPath)

    $candidates = @($ConfiguredPath, "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat", "C:\Xilinx\Vivado\2024.1\bin\bootgen.bat")
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "bootgen was not found. Pass -BootgenPath explicitly."
}

function Resolve-TimingReportPath {
    param([string]$Workspace)

    $candidates = @(
        (Join-Path $Workspace "HCS_SOC.runs\impl_1\stream_smoke_dma_wrapper_timing_summary_postroute_physopted.rpt")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $match = Get-ChildItem -Path $Workspace -Recurse -File -Filter "*timing_summary_postroute_physopted.rpt" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -ne $match) {
        return $match.FullName
    }

    return $null
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

foreach ($requiredPath in @($platformScript, $patchScript, $appBuildScript, $templateBif, $XsctBat, $timingParserScript)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required stream-smoke build input not found: $requiredPath"
    }
}
if (-not (Test-Path $XsaPath)) {
    throw "Fresh stream_smoke_dma_wrapper.xsa not found: $XsaPath"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
foreach ($staleArtifact in @(
    "BOOT.BIN",
    "fsbl.elf",
    "stream_smoke_dma_wrapper.bit",
    "ax7020_dma_raw_copy_stream_smoke_app.elf",
    "bootgen_read.txt",
    "readme.txt"
)) {
    $stalePath = Join-Path $OutputDir $staleArtifact
    if (Test-Path $stalePath) {
        Remove-Item -Force -LiteralPath $stalePath
    }
}

$workspaceParent = Split-Path -Parent $WorkspaceRoot
$xsaExtractDir = Join-Path $workspaceParent "xsa_extract"
$timingReport = Resolve-TimingReportPath -Workspace $workspace

& $platformScript -XsctBat $XsctBat -XsaPath $XsaPath -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
if ($LASTEXITCODE -ne 0) {
    throw "Dedicated stream-smoke platform generation failed"
}

& $patchScript -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName -VitisRoot $VitisRoot
if ($LASTEXITCODE -ne 0) {
    throw "Official dedicated stream-smoke FSBL stabilization failed"
}

if (Test-Path $xsaExtractDir) {
    Remove-Item -Recurse -Force $xsaExtractDir
}
New-Item -ItemType Directory -Force -Path $xsaExtractDir | Out-Null
tar -xf $XsaPath -C $xsaExtractDir
if ($LASTEXITCODE -ne 0) {
    throw "Failed to extract stream-smoke XSA: $XsaPath"
}

$bitstream = Get-ChildItem -Path $xsaExtractDir -File -Filter *.bit |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $bitstream) {
    throw "No bitstream found inside dedicated stream-smoke XSA: $XsaPath"
}

$fsblElf = Resolve-StreamSmokeFsblElf -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
if ($null -eq $fsblElf) {
    throw "Fresh stream-smoke fsbl.elf not found under $WorkspaceRoot"
}
$platformSwDir = Resolve-StreamSmokeApiBspRoot -WorkspaceRoot $WorkspaceRoot

& $appBuildScript -VitisRoot $VitisRoot -PlatformSwDir $platformSwDir
if ($LASTEXITCODE -ne 0) {
    throw "Stream-smoke app build failed"
}

foreach ($requiredPath in @($appElf, $fsblElf.FullName, $bitstream.FullName)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required stream-smoke boot artifact not found: $requiredPath"
    }
}

$bootgen = Resolve-BootgenExecutable -ConfiguredPath $BootgenPath

$stagedFsbl = Join-Path $OutputDir "fsbl.elf"
$stagedBit = Join-Path $OutputDir "stream_smoke_dma_wrapper.bit"
$stagedApp = Join-Path $OutputDir "ax7020_dma_raw_copy_stream_smoke_app.elf"
$bootBin = Join-Path $OutputDir "BOOT.BIN"
$bootRead = Join-Path $OutputDir "bootgen_read.txt"
$readmePath = Join-Path $OutputDir "readme.txt"

Copy-Item -Path $fsblElf.FullName -Destination $stagedFsbl -Force
Copy-Item -Path $bitstream.FullName -Destination $stagedBit -Force
Copy-Item -Path $appElf -Destination $stagedApp -Force

Push-Location $OutputDir
try {
    & $bootgen -image $templateBif -arch zynq -o $bootBin -w
    if ($LASTEXITCODE -ne 0) {
        throw "bootgen failed for dedicated stream-smoke BOOT.BIN"
    }

    $readback = & $bootgen -read $bootBin 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "bootgen -read failed for dedicated stream-smoke BOOT.BIN"
    }
    Set-Content -Path $bootRead -Value $readback -Encoding ASCII
}
finally {
    Pop-Location
}

$bootHash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash
$timingSummary = $null
if ($null -ne $timingReport) {
    $timingSummary = & $timingParserScript -ReportPath $timingReport -Quiet
}

$readme = @"
AX7020 Stream Smoke DMA

Purpose:
- Dedicated Phase 3 stream-smoke image for stream-mode DMA.
- Current status: experimental dedicated with-bit path kept for FSBL root-cause work.
- This is not the current board-proven Phase 3 baseline.
- Uses a delay-only dedicated FSBL stabilization in the with-bit handoff window.
- Validates EXACT_FIT, SHORT, and OVERFLOW / missing TLAST handling using a stream dummy source block.
- word-granular only in this phase: packet lengths are restricted to 4-byte multiples.
- No IRQ path is used in this smoke line.

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from stream_smoke_dma_wrapper.xsa
2. fresh stream_smoke_dma_wrapper.bit extracted from that same XSA
3. stream-smoke application ELF

Fresh source chain:
- Vivado project: HCS_SOC.xpr
- XSA path: $XsaPath
- XSA extract dir: $xsaExtractDir
- Bitstream path: $($bitstream.FullName)
- XSCT workspace: $WorkspaceRoot
- Platform name: $PlatformName
- FSBL path: $($fsblElf.FullName)
- FSBL stabilization: delay-only, two fixed spins in FsblHandoff() with-bit path
- App API BSP root: $platformSwDir
- App ELF path: $appElf
- SHA256: $bootHash
$(if ($timingSummary) {
"- Timing summary:
  WNS = $($timingSummary.SetupWnsNs) ns
  TNS = $($timingSummary.SetupTnsNs) ns
  setup failing endpoints = $($timingSummary.SetupFailingEndpoints)
  WHS = $($timingSummary.HoldWhsNs) ns
  THS = $($timingSummary.HoldThsNs) ns
  hold failing endpoints = $($timingSummary.HoldFailingEndpoints)"
} else {
"- Timing summary: report not found"
})

Current board validation policy:
- dedicated stream-smoke with-bit path is still blocked by the dedicated stream-smoke FSBL
- use the temporary board-proven baseline for Phase 3 board validation:
  design1 fsbl.elf + stream_smoke_dma_wrapper.bit + ax7020_dma_raw_copy_stream_smoke_app.elf
- do not promote this image until it passes 3 consecutive cold boots
"@

Set-Content -Path $readmePath -Value $readme -Encoding ASCII

Write-Host "Generated dedicated stream-smoke BOOT.BIN:"
Write-Host $bootBin
Write-Host "Fresh XSA: $XsaPath"
Write-Host "Fresh FSBL: $($fsblElf.FullName)"
Write-Host "Fresh bitstream: $($bitstream.FullName)"
Write-Host "bootgen -read: $bootRead"
Write-Host "SHA256: $bootHash"
