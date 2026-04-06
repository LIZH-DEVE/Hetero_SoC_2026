[CmdletBinding()]
param(
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
    [string]$StreamSmokeXsa = "",
    [string]$Design1Fsbl = "",
    [string]$Design1UartAppElf = "",
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

if ([string]::IsNullOrWhiteSpace($StreamSmokeXsa)) {
    $StreamSmokeXsa = Join-Path $workspace "stream_smoke_dma_wrapper.xsa"
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
if ([string]::IsNullOrWhiteSpace($Design1UartAppElf)) {
    $Design1UartAppElf = Resolve-ExistingFile -Label "design_1 UART app ELF" -Candidates @(
        (Join-Path $workspace "ax7020_repo_design1_uart_baseline_app\build\ax7020_repo_design1_uart_baseline_app.elf")
    )
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $workspace "sd_boot\ax7020_streamsmokebit_design1_uart"
}

$bootBuildScript = Join-Path $workspace "build_boot_bin.ps1"
$xsaExtractDir = Join-Path $workspace "streamsmokebit_design1_uart_xsa_extract"

foreach ($requiredPath in @($bootBuildScript, $BootgenPath, $StreamSmokeXsa, $Design1Fsbl, $Design1UartAppElf)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required streamsmokebit-design1-uart input not found: $requiredPath"
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
foreach ($staleArtifact in @(
    "BOOT.BIN",
    "fsbl.elf",
    "stream_smoke_dma_wrapper.bit",
    "ax7020_repo_design1_uart_baseline_app.elf",
    "bootgen_read.txt",
    "readme.txt"
)) {
    $stalePath = Join-Path $OutputDir $staleArtifact
    if (Test-Path $stalePath) {
        Remove-Item -Force -LiteralPath $stalePath
    }
}

if (Test-Path $xsaExtractDir) {
    Remove-Item -Recurse -Force $xsaExtractDir
}
New-Item -ItemType Directory -Force -Path $xsaExtractDir | Out-Null
tar -xf $StreamSmokeXsa -C $xsaExtractDir
if ($LASTEXITCODE -ne 0) {
    throw "Failed to extract XSA: $StreamSmokeXsa"
}

$streamBitstream = Get-ChildItem -Path $xsaExtractDir -File -Filter *.bit |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $streamBitstream) {
    throw "No stream-smoke bitstream found inside XSA: $StreamSmokeXsa"
}

$stagedFsbl = Join-Path $OutputDir "fsbl.elf"
$stagedBit = Join-Path $OutputDir "stream_smoke_dma_wrapper.bit"
$stagedApp = Join-Path $OutputDir "ax7020_repo_design1_uart_baseline_app.elf"

Copy-Item -Path $Design1Fsbl -Destination $stagedFsbl -Force
Copy-Item -Path $streamBitstream.FullName -Destination $stagedBit -Force
Copy-Item -Path $Design1UartAppElf -Destination $stagedApp -Force

& powershell -ExecutionPolicy Bypass -File $bootBuildScript `
    -BootgenPath $BootgenPath `
    -FsblElf $stagedFsbl `
    -Bitstream $stagedBit `
    -AppElf $stagedApp `
    -OutputDir $OutputDir
if ($LASTEXITCODE -ne 0) {
    throw "boot image generation failed for streamsmokebit-design1-uart image"
}

$bootBin = Join-Path $OutputDir "BOOT.BIN"
$bootRead = Join-Path $OutputDir "bootgen_read.txt"
$readmePath = Join-Path $OutputDir "readme.txt"
$stagedFsbl = Join-Path $OutputDir "fsbl.elf"
$stagedBit = Join-Path $OutputDir "stream_smoke_dma_wrapper.bit"
$stagedApp = Join-Path $OutputDir "ax7020_repo_design1_uart_baseline_app.elf"

Copy-Item -Path $Design1Fsbl -Destination $stagedFsbl -Force
Copy-Item -Path $streamBitstream.FullName -Destination $stagedBit -Force
Copy-Item -Path $Design1UartAppElf -Destination $stagedApp -Force

$readback = & $BootgenPath -read $bootBin 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "bootgen -read failed for streamsmokebit-design1-uart BOOT.BIN"
}
Set-Content -Path $bootRead -Value $readback -Encoding ASCII

$bootHash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash
$readme = @"
AX7020 stream-smoke-bit + design1-UART Diagnostic

Purpose:
- Use a known-good design_1 FSBL + known-good design_1 UART app with the
  dedicated stream-smoke bitstream.
- If this image stays silent, the stream-smoke bitstream itself is sufficient
  to break board bring-up.

Clean boot image structure:
1. [bootloader] known-good repo design_1 fsbl.elf
2. dedicated stream_smoke_dma_wrapper.bit
3. known-good repo design_1 UART baseline app ELF

Source chain:
- Stream-smoke XSA: $StreamSmokeXsa
- Stream-smoke bitstream: $stagedBit
- design_1 FSBL: $stagedFsbl
- design_1 UART app ELF: $stagedApp
- SHA256: $bootHash

Expected board-side behavior:
- UART should print at least:
  REPO DESIGN1 UART BASELINE
"@

Set-Content -Path $readmePath -Value $readme -Encoding ASCII

Write-Host "Generated streamsmokebit-design1-uart BOOT.BIN:"
Write-Host $bootBin
Write-Host "Stream-smoke XSA: $StreamSmokeXsa"
Write-Host "Stream-smoke bitstream: $stagedBit"
Write-Host "design_1 FSBL: $stagedFsbl"
Write-Host "design_1 UART app ELF: $stagedApp"
Write-Host "bootgen -read: $bootRead"
Write-Host "SHA256: $bootHash"
