[CmdletBinding()]
param(
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
    [string]$Design1Fsbl = "",
    [string]$StreamSmokeBitstream = "",
    [string]$StreamSmokeAppElf = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path

function Resolve-ExistingFile {
    param(
        [string[]]$Candidates,
        [string]$Label
    )

    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "$Label not found. Checked: $($Candidates -join '; ')"
}

function Resolve-LatestByPattern {
    param(
        [string]$Root,
        [string]$Filter,
        [string]$Label
    )

    if (-not (Test-Path $Root)) {
        throw "$Label search root not found: $Root"
    }

    $match = Get-ChildItem -Path $Root -Recurse -Filter $Filter -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $match) {
        throw "$Label not found under: $Root"
    }

    return $match.FullName
}

if ([string]::IsNullOrWhiteSpace($Design1Fsbl)) {
    $design1FsblCandidates = @(
        (Join-Path $workspace "sd_boot\ax7020_repo_design1_uart_baseline\fsbl.elf")
    )
    $design1WorkspaceRoot = Join-Path $workspace "repo_design1_uart_baseline_xsct\workspace"
    if (Test-Path $design1WorkspaceRoot) {
        $design1FsblCandidates += Resolve-LatestByPattern -Root $design1WorkspaceRoot -Filter "fsbl.elf" -Label "design_1 FSBL"
    }
    $design1AltRoot = Join-Path $workspace "sd_boot\ax7020_design1fsbl_raw_copy_app"
    if (Test-Path $design1AltRoot) {
        $design1FsblCandidates += Resolve-LatestByPattern -Root $design1AltRoot -Filter "fsbl.elf" -Label "design_1 FSBL"
    }
    $Design1Fsbl = Resolve-ExistingFile -Label "design_1 FSBL" -Candidates $design1FsblCandidates
}
if ([string]::IsNullOrWhiteSpace($StreamSmokeBitstream)) {
    $StreamSmokeBitstream = Resolve-ExistingFile -Label "stream-smoke bitstream" -Candidates @(
        (Join-Path $workspace "sd_boot\ax7020_dma_raw_copy_stream_smoke\stream_smoke_dma_wrapper.bit"),
        (Join-Path $workspace "sd_boot\ax7020_streamsmokebit_design1_uart\stream_smoke_dma_wrapper.bit")
    )
}
if ([string]::IsNullOrWhiteSpace($StreamSmokeAppElf)) {
    $StreamSmokeAppElf = Resolve-ExistingFile -Label "stream-smoke app ELF" -Candidates @(
        (Join-Path $workspace "ax7020_dma_raw_copy_stream_smoke_app\build\ax7020_dma_raw_copy_stream_smoke_app.elf")
    )
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $workspace "sd_boot\ax7020_design1fsbl_stream_smoke_app"
}

$bootBuildScript = Join-Path $workspace "build_boot_bin.ps1"

foreach ($requiredPath in @($bootBuildScript, $BootgenPath, $Design1Fsbl, $StreamSmokeBitstream, $StreamSmokeAppElf)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required design1fsbl-stream-smoke-app input not found: $requiredPath"
    }
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

$stagedFsbl = Join-Path $OutputDir "fsbl.elf"
$stagedBit = Join-Path $OutputDir "stream_smoke_dma_wrapper.bit"
$stagedApp = Join-Path $OutputDir "ax7020_dma_raw_copy_stream_smoke_app.elf"

Copy-Item -Path $Design1Fsbl -Destination $stagedFsbl -Force
Copy-Item -Path $StreamSmokeBitstream -Destination $stagedBit -Force
Copy-Item -Path $StreamSmokeAppElf -Destination $stagedApp -Force

& powershell -ExecutionPolicy Bypass -File $bootBuildScript `
    -BootgenPath $BootgenPath `
    -FsblElf $stagedFsbl `
    -Bitstream $stagedBit `
    -AppElf $stagedApp `
    -OutputDir $OutputDir
if ($LASTEXITCODE -ne 0) {
    throw "boot image generation failed for design1fsbl-stream-smoke-app image"
}

$bootBin = Join-Path $OutputDir "BOOT.BIN"
$bootRead = Join-Path $OutputDir "bootgen_read.txt"
$readmePath = Join-Path $OutputDir "readme.txt"

$readback = & $BootgenPath -read $bootBin 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "bootgen -read failed for design1fsbl-stream-smoke-app BOOT.BIN"
}
Set-Content -Path $bootRead -Value $readback -Encoding ASCII

$bootHash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash
$readme = @"
AX7020 design1-FSBL + stream-smoke-app Diagnostic

Purpose:
- Temporary board-proven Phase 3 baseline for stream-mode DMA.
- Uses the known-good repo design_1 FSBL with the dedicated stream-smoke bitstream
  and the dedicated stream-smoke app.
- This image currently proves that stream-smoke app + bitstream + data path are valid on hardware,
  while the dedicated stream-smoke FSBL remains the only unresolved with-bit blocker.

Clean boot image structure:
1. [bootloader] known-good repo design_1 fsbl.elf
2. dedicated stream_smoke_dma_wrapper.bit
3. dedicated stream-smoke app ELF

Source chain:
- design_1 FSBL: $stagedFsbl
- stream-smoke bitstream: $stagedBit
- stream-smoke app ELF: $stagedApp
- SHA256: $bootHash

Expected board-side behavior:
- UART prints:
  DMA stream smoke image
  STREAM_STAGE EXACT_FIT PASS actual_len=1024
  STREAM_STAGE SHORT PASS actual_len=64
  STREAM_STAGE OVERFLOW PASS actual_len=64
  DMA stream smoke PASS
"@

Set-Content -Path $readmePath -Value $readme -Encoding ASCII

Write-Host "Generated design1fsbl-stream-smoke-app BOOT.BIN:"
Write-Host $bootBin
Write-Host "Design1 FSBL: $stagedFsbl"
Write-Host "Stream-smoke bitstream: $stagedBit"
Write-Host "Stream-smoke app ELF: $stagedApp"
Write-Host "bootgen -read: $bootRead"
Write-Host "SHA256: $bootHash"
