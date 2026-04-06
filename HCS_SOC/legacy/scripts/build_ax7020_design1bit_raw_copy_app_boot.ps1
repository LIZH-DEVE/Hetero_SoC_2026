[CmdletBinding()]
param(
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
    [string]$Design1Fsbl = "",
    [string]$Design1Bitstream = "",
    [string]$RawCopyAppElf = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($Design1Fsbl)) {
    $Design1Fsbl = Join-Path $workspace "repo_design1_uart_baseline_xsct\workspace\ax7020_repo_design1_uart_platform\zynq_fsbl\fsbl.elf"
}
if ([string]::IsNullOrWhiteSpace($Design1Bitstream)) {
    $Design1Bitstream = Join-Path $workspace "design_1_wrapper.bit"
}
if ([string]::IsNullOrWhiteSpace($RawCopyAppElf)) {
    $RawCopyAppElf = Join-Path $workspace "ax7020_dma_raw_copy_smoke_app\build\ax7020_dma_raw_copy_smoke_app.elf"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $workspace "sd_boot\ax7020_design1bit_raw_copy_app"
}

$bootBuildScript = Join-Path $workspace "build_boot_bin.ps1"

foreach ($requiredPath in @($bootBuildScript, $BootgenPath, $Design1Fsbl, $Design1Bitstream, $RawCopyAppElf)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required design1-bit raw-copy-app input not found: $requiredPath"
    }
}

& powershell -ExecutionPolicy Bypass -File $bootBuildScript `
    -BootgenPath $BootgenPath `
    -FsblElf $Design1Fsbl `
    -Bitstream $Design1Bitstream `
    -AppElf $RawCopyAppElf `
    -OutputDir $OutputDir
if ($LASTEXITCODE -ne 0) {
    throw "boot image generation failed for design1-bit raw-copy-app image"
}

$bootBin = Join-Path $OutputDir "BOOT.BIN"
$bootRead = Join-Path $OutputDir "bootgen_read.txt"
$readmePath = Join-Path $OutputDir "readme.txt"

$readback = & $BootgenPath -read $bootBin 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "bootgen -read failed for design1-bit raw-copy-app BOOT.BIN"
}
Set-Content -Path $bootRead -Value $readback -Encoding ASCII

$bootHash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash
$readme = @"
AX7020 design1-bit + raw-copy-app Diagnostic

Purpose:
- Use the known-good repo design_1 FSBL + design_1 bitstream chain with the
  dedicated raw-copy smoke app.
- If this image prints RAWCOPY_STAGE markers, the raw-copy app/runtime is alive
  and the remaining blocker is in the dedicated raw-copy hardware/boot chain.

Clean boot image structure:
1. [bootloader] repo design_1 fresh fsbl.elf
2. repo design_1 fresh bitstream
3. raw-copy smoke application ELF

Source chain:
- Repo design_1 FSBL path: $Design1Fsbl
- Repo design_1 bitstream path: $Design1Bitstream
- Raw-copy app ELF path: $RawCopyAppElf
- SHA256: $bootHash

Expected board-side behavior:
- UART should print at least:
  DMA raw-copy smoke image
  RAWCOPY_STAGE INIT
"@

Set-Content -Path $readmePath -Value $readme -Encoding ASCII

Write-Host "Generated design1-bit raw-copy-app BOOT.BIN:"
Write-Host $bootBin
Write-Host "Design1 FSBL: $Design1Fsbl"
Write-Host "Design1 bitstream: $Design1Bitstream"
Write-Host "Raw-copy app ELF: $RawCopyAppElf"
Write-Host "bootgen -read: $bootRead"
Write-Host "SHA256: $bootHash"
