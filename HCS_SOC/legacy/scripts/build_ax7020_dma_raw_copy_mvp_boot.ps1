[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$VitisRoot = "D:\Xilinx\Vitis\2024.1",
    [string]$XsctBat = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat",
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
$appBuildScript = Join-Path $workspace "build_ax7020_dma_raw_copy_mvp_app.ps1"
$templateBif = Join-Path $workspace "sd_boot\ax7020_dma_raw_copy_mvp\boot.bif"
$appElf = Join-Path $workspace "ax7020_dma_raw_copy_mvp_app\build\ax7020_dma_raw_copy_mvp_app.elf"
$timingParserScript = Join-Path $workspace "read_vivado_timing_summary.ps1"

if ([string]::IsNullOrWhiteSpace($XsaPath)) {
    $XsaPath = Join-Path $workspace "raw_copy_dma_wrapper.xsa"
}
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Join-Path $workspace "ax7020_dma_raw_copy_platform_xsct\workspace"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $workspace "sd_boot\ax7020_dma_raw_copy_mvp"
}

function Resolve-RawCopyApiBspRoot {
    param([string]$WorkspaceRoot)

    $candidates = @(
        (Join-Path $WorkspaceRoot "ax7020_dma_raw_copy_platform\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0"),
        (Join-Path $WorkspaceRoot "standalone_bsp\ps7_cortexa9_0")
    )

    foreach ($candidate in $candidates) {
        if ((Test-Path $candidate) -and (Test-Path (Join-Path $candidate "include\xparameters.h"))) {
            return $candidate
        }
    }

    throw "Fresh raw-copy API BSP root not found under $WorkspaceRoot"
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

foreach ($requiredPath in @($exportScript, $platformScript, $appBuildScript, $templateBif, $XsctBat, $timingParserScript)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required raw-copy MVP build input not found: $requiredPath"
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
foreach ($staleArtifact in @(
    "BOOT.BIN",
    "fsbl.elf",
    "dma_raw_copy_mvp.bit",
    "ax7020_dma_raw_copy_mvp_app.elf",
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
$timingReport = Join-Path $workspace "HCS_SOC.runs\impl_1\raw_copy_dma_wrapper_timing_summary_postroute_physopted.rpt"
$previousXsaWriteUtc = $null
if (Test-Path $XsaPath) {
    $previousXsaWriteUtc = (Get-Item $XsaPath).LastWriteTimeUtc
}

& $exportScript -VivadoBat $VivadoBat -XsaPath $XsaPath
if ($LASTEXITCODE -ne 0) {
    throw "Fresh raw-copy XSA export failed"
}

if (-not (Test-Path $XsaPath)) {
    throw "Fresh raw-copy XSA not found after export: $XsaPath"
}

if (($null -ne $previousXsaWriteUtc) -and ((Get-Item $XsaPath).LastWriteTimeUtc -le $previousXsaWriteUtc)) {
    throw "Fresh raw-copy XSA export did not update $XsaPath; refusing to package stale hardware"
}

& $platformScript -XsctBat $XsctBat -XsaPath $XsaPath -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
if ($LASTEXITCODE -ne 0) {
    throw "Dedicated raw-copy platform generation failed"
}

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
    throw "No bitstream found inside dedicated raw-copy XSA: $XsaPath"
}

$fsblElf = Get-ChildItem -Path $WorkspaceRoot -Recurse -File -Filter fsbl.elf |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $fsblElf) {
    throw "Fresh raw-copy fsbl.elf not found under $WorkspaceRoot"
}
$platformSwDir = Resolve-RawCopyApiBspRoot -WorkspaceRoot $WorkspaceRoot

& $appBuildScript -VitisRoot $VitisRoot -PlatformSwDir $platformSwDir
if ($LASTEXITCODE -ne 0) {
    throw "Raw-copy MVP app build failed"
}

foreach ($requiredPath in @($appElf, $fsblElf.FullName, $bitstream.FullName)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required raw-copy MVP boot artifact not found: $requiredPath"
    }
}

$bootgen = Resolve-BootgenExecutable -ConfiguredPath $BootgenPath
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$stagedFsbl = Join-Path $OutputDir "fsbl.elf"
$stagedBit = Join-Path $OutputDir "dma_raw_copy_mvp.bit"
$stagedApp = Join-Path $OutputDir "ax7020_dma_raw_copy_mvp_app.elf"
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
        throw "bootgen failed for dedicated raw-copy MVP BOOT.BIN"
    }

    $readback = & $bootgen -read $bootBin 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "bootgen -read failed for dedicated raw-copy MVP BOOT.BIN"
    }
    Set-Content -Path $bootRead -Value $readback -Encoding ASCII
}
finally {
    Pop-Location
}

$bootHash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash
$timingSummary = $null
if (Test-Path $timingReport) {
    $timingSummary = & $timingParserScript -ReportPath $timingReport -Quiet
}

$readme = @"
AX7020 Low-LUT Raw-Copy DMA MVP

Purpose:
- Dedicated low-LUT board-smoke image for Phase 2 fixed-mode DMA MVP.
- Validates 3 successful descriptors, 4th submit returns -5, and IRQ coalescing count/timeout paths.
- 3 descriptors staged while hardware is quiesced.
- 4th staged submit returns -5 before the doorbell is rung.
- Explicit ring/doorbell release then starts hardware consumption.

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from raw_copy_dma_wrapper.xsa
2. fresh raw_copy_dma_wrapper.bit extracted from that same XSA
3. raw-copy MVP application ELF

Fresh source chain:
- Vivado project: HCS_SOC.xpr
- XSA export script: export_raw_copy_dma_xsa.ps1 / export_raw_copy_dma_xsa.tcl
- XSA path: $XsaPath
- XSA extract dir: $xsaExtractDir
- Bitstream path: $($bitstream.FullName)
- XSCT workspace: $WorkspaceRoot
- Platform name: $PlatformName
- FSBL path: $($fsblElf.FullName)
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
"- Timing summary: report not found at $timingReport"
})

Expected board-side behavior:
- UART prints:
  DMA raw-copy MVP image
  MVP_STAGE RING_FULL_CHECK submit rc[3]=-5
  MVP_IRQ_CONFIG count=2 timeout=64 cycles
  MVP_IRQ_COUNT status=0x...
  MVP_IRQ_TIMEOUT status=0x...
  DMA raw-copy MVP PASS
"@

Set-Content -Path $readmePath -Value $readme -Encoding ASCII

Write-Host "Generated dedicated raw-copy MVP BOOT.BIN:"
Write-Host $bootBin
Write-Host "Fresh XSA: $XsaPath"
Write-Host "Fresh FSBL: $($fsblElf.FullName)"
Write-Host "Fresh bitstream: $($bitstream.FullName)"
Write-Host "bootgen -read: $bootRead"
Write-Host "SHA256: $bootHash"
