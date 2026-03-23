[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\\Xilinx\\Vitis\\2024.1",
    [string]$OfficialRoot = "D:\\FPGAhanjia\\Hetero_SoC_2026_3\\AX7020_2023.1\\course_s2_vitis\\06_net_test\\Vitis\\design_1_wrapper",
    [ValidateSet("read_only", "write_ctrl", "write_key_1c", "write_key_18", "write_key_14", "write_key_10")]
    [string]$TestCase = "read_only",
    [string]$BootgenPath
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildAppScript = Join-Path $workspace "build_ax7020_crypto_direct_write_smoke_official_app.ps1"
$buildBootScript = Join-Path $workspace "build_boot_bin.ps1"
$buildDir = Join-Path $workspace "ax7020_crypto_direct_write_smoke_official_app\\build\\$TestCase"
$appElf = Join-Path $buildDir "ax7020_crypto_direct_write_smoke_official_app.elf"
$outputDir = Join-Path $workspace "sd_boot\\crypto_direct_write_smoke_official\\$TestCase"
$fsblElf = Join-Path $OfficialRoot "zynq_fsbl\\fsbl.elf"
$bitstream = Join-Path $workspace "platform\\export\\platform\\hw\\design_1_wrapper.bit"

foreach ($path in @($buildAppScript, $buildBootScript, $fsblElf, $bitstream)) {
    if (-not (Test-Path $path)) {
        throw "Required path not found: $path"
    }
}

& $buildAppScript -VitisRoot $VitisRoot -OfficialRoot $OfficialRoot -TestCase $TestCase
if ($LASTEXITCODE -ne 0) {
    throw "Official smoke app build failed."
}

if (-not (Test-Path $appElf)) {
    throw "Official smoke app ELF not found: $appElf"
}

& $buildBootScript `
    -BootgenPath $BootgenPath `
    -FsblElf $fsblElf `
    -Bitstream $bitstream `
    -AppElf $appElf `
    -OutputDir $outputDir

if ($LASTEXITCODE -ne 0) {
    throw "Failed to package official smoke BOOT.BIN."
}

$bootBin = Join-Path $outputDir "BOOT.BIN"
$hash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash

Write-Host "Official smoke boot image ready:"
Write-Host $bootBin
Write-Host "Test case: $TestCase"
Write-Host "SHA256: $hash"
