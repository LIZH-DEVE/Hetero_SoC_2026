[CmdletBinding()]
param(
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
    [string]$Design1Fsbl = "",
    [string]$RawCopyAppElf = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateBif = Join-Path $workspace "sd_boot\ax7020_design1fsbl_raw_copy_app_nobit\boot.bif"

if ([string]::IsNullOrWhiteSpace($Design1Fsbl)) {
    $Design1Fsbl = Join-Path $workspace "sd_boot\ax7020_repo_design1_uart_baseline\fsbl.elf"
    if (-not (Test-Path $Design1Fsbl)) {
        $Design1Fsbl = Join-Path $workspace "repo_design1_uart_baseline_xsct\workspace\ax7020_repo_design1_uart_platform\zynq_fsbl\fsbl.elf"
    }
}
if ([string]::IsNullOrWhiteSpace($RawCopyAppElf)) {
    $RawCopyAppElf = Join-Path $workspace "ax7020_dma_raw_copy_smoke_app\build\ax7020_dma_raw_copy_smoke_app.elf"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $workspace "sd_boot\ax7020_design1fsbl_raw_copy_app_nobit"
}

foreach ($requiredPath in @($templateBif, $Design1Fsbl, $RawCopyAppElf, $BootgenPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required design1-FSBL raw-copy-app no-bit input not found: $requiredPath"
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$stagedFsbl = Join-Path $OutputDir "fsbl.elf"
$stagedApp = Join-Path $OutputDir "ax7020_dma_raw_copy_smoke_app.elf"
$bootBin = Join-Path $OutputDir "BOOT.BIN"
$bootRead = Join-Path $OutputDir "bootgen_read.txt"
$readmePath = Join-Path $OutputDir "readme.txt"

Copy-Item -Path $Design1Fsbl -Destination $stagedFsbl -Force
Copy-Item -Path $RawCopyAppElf -Destination $stagedApp -Force

Push-Location $OutputDir
try {
    & $BootgenPath -image $templateBif -arch zynq -o $bootBin -w
    if ($LASTEXITCODE -ne 0) {
        throw "bootgen failed for design1-FSBL raw-copy-app no-bit BOOT.BIN"
    }

    $readback = & $BootgenPath -read $bootBin 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "bootgen -read failed for design1-FSBL raw-copy-app no-bit BOOT.BIN"
    }
    Set-Content -Path $bootRead -Value $readback -Encoding ASCII
}
finally {
    Pop-Location
}

$bootHash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash
$readme = @"
AX7020 Design1-FSBL + Raw-Copy-App No-Bit Diagnostic

Purpose:
- Isolate raw-copy app/runtime by combining the known-good repo design_1 FSBL
  with the dedicated raw-copy smoke app.
- Omits the PL bitstream on purpose.

Clean boot image structure:
1. [bootloader] repo design_1 fresh fsbl.elf
2. raw-copy smoke application ELF

Source chain:
- Repo design_1 FSBL path: $Design1Fsbl
- Raw-copy app ELF path: $RawCopyAppElf
- SHA256: $bootHash

Expected board-side behavior:
- UART prints at least:
  RAWCOPY_STAGE INIT
"@

Set-Content -Path $readmePath -Value $readme -Encoding ASCII

Write-Host "Generated design1-FSBL raw-copy-app no-bit BOOT.BIN:"
Write-Host $bootBin
Write-Host "Repo design_1 FSBL: $Design1Fsbl"
Write-Host "Raw-copy app ELF: $RawCopyAppElf"
Write-Host "bootgen -read: $bootRead"
Write-Host "SHA256: $bootHash"
