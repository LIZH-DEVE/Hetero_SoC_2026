[CmdletBinding()]
param(
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
    [string]$Design1Fsbl = "",
    [string]$RepoDesign1AppElf = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateBif = Join-Path $workspace "sd_boot\ax7020_repo_design1_uart_baseline_nobit\boot.bif"

if ([string]::IsNullOrWhiteSpace($Design1Fsbl)) {
    $Design1Fsbl = Join-Path $workspace "sd_boot\ax7020_repo_design1_uart_baseline\fsbl.elf"
    if (-not (Test-Path $Design1Fsbl)) {
        $Design1Fsbl = Join-Path $workspace "repo_design1_uart_baseline_xsct\workspace\ax7020_repo_design1_uart_platform\zynq_fsbl\fsbl.elf"
    }
}
if ([string]::IsNullOrWhiteSpace($RepoDesign1AppElf)) {
    $RepoDesign1AppElf = Join-Path $workspace "ax7020_repo_design1_uart_baseline_app\build\ax7020_repo_design1_uart_baseline_app.elf"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $workspace "sd_boot\ax7020_repo_design1_uart_baseline_nobit"
}

foreach ($requiredPath in @($templateBif, $Design1Fsbl, $RepoDesign1AppElf, $BootgenPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required repo design1 no-bit input not found: $requiredPath"
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$stagedFsbl = Join-Path $OutputDir "fsbl.elf"
$stagedApp = Join-Path $OutputDir "ax7020_repo_design1_uart_baseline_app.elf"
$bootBin = Join-Path $OutputDir "BOOT.BIN"
$bootRead = Join-Path $OutputDir "bootgen_read.txt"
$readmePath = Join-Path $OutputDir "readme.txt"

Copy-Item -Path $Design1Fsbl -Destination $stagedFsbl -Force
Copy-Item -Path $RepoDesign1AppElf -Destination $stagedApp -Force

Push-Location $OutputDir
try {
    & $BootgenPath -image $templateBif -arch zynq -o $bootBin -w
    if ($LASTEXITCODE -ne 0) {
        throw "bootgen failed for repo design1 no-bit BOOT.BIN"
    }

    $readback = & $BootgenPath -read $bootBin 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "bootgen -read failed for repo design1 no-bit BOOT.BIN"
    }
    Set-Content -Path $bootRead -Value $readback -Encoding ASCII
}
finally {
    Pop-Location
}

$bootHash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash
$readme = @"
AX7020 Repo design_1 UART Baseline (No-Bit Diagnostic)

Purpose:
- Control image to verify whether repo-generated no-bit boot images can
  reach the known-good design_1 UART baseline application without PL load.

Clean boot image structure:
1. [bootloader] repo design_1 fresh fsbl.elf
2. repo design_1 UART baseline application ELF

Source chain:
- Repo design_1 FSBL path: $Design1Fsbl
- Repo design_1 baseline app ELF path: $RepoDesign1AppElf
- SHA256: $bootHash

Expected board-side behavior:
- UART prints:
  REPO DESIGN1 UART BASELINE
  UART1 OK
  FRESH_XSA_FSBL_CHAIN
  REPO_HEARTBEAT N
"@

Set-Content -Path $readmePath -Value $readme -Encoding ASCII

Write-Host "Generated repo design1 no-bit BOOT.BIN:"
Write-Host $bootBin
Write-Host "Repo design_1 FSBL: $Design1Fsbl"
Write-Host "Repo design_1 app ELF: $RepoDesign1AppElf"
Write-Host "bootgen -read: $bootRead"
Write-Host "SHA256: $bootHash"
