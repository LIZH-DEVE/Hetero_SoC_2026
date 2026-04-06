[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\Xilinx\Vitis\2023.1",
    [string[]]$TestCase = @("read_only"),
    [switch]$AllCases,
    [string]$BootgenPath,
    [string]$FsblElf = "D:\FPGAhanjia\Hetero_SoC_2026_3\AX7020_2023.1\course_s2_vitis\06_net_test\Vitis\design_1_wrapper\zynq_fsbl\fsbl.elf",
    [string]$Bitstream = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\platform\export\platform\hw\design_1_wrapper.bit"
)

$ErrorActionPreference = "Stop"

if ($AllCases) {
    $TestCase = @(
        "read_only",
        "write_ctrl",
        "write_key_1c",
        "write_key_18",
        "write_key_14",
        "write_key_10"
    )
}

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildAppScript = Join-Path $workspace "build_crypto_direct_write_smoke_app.ps1"
$buildBootScript = Join-Path $workspace "build_boot_bin.ps1"
$buildRoot = Join-Path $workspace "crypto_direct_write_smoke_app\build"
$sdBootRoot = Join-Path $workspace "sd_boot\crypto_direct_write_smoke"

foreach ($path in @($buildAppScript, $buildBootScript, $FsblElf, $Bitstream)) {
    if (-not (Test-Path $path)) {
        throw "Required path not found: $path"
    }
}

& $buildAppScript -VitisRoot $VitisRoot -TestCase $TestCase
if ($LASTEXITCODE -ne 0) {
    throw "Smoke app build failed."
}

foreach ($caseName in $TestCase) {
    $appElf = Join-Path $buildRoot $caseName
    $appElf = Join-Path $appElf "ax7020_crypto_direct_write_smoke_$caseName.elf"
    $outputDir = Join-Path $sdBootRoot $caseName

    if (-not (Test-Path $appElf)) {
        throw "Smoke app ELF not found for test case '$caseName': $appElf"
    }

    & $buildBootScript `
        -BootgenPath $BootgenPath `
        -FsblElf $FsblElf `
        -Bitstream $Bitstream `
        -AppElf $appElf `
        -OutputDir $outputDir

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to package BOOT.BIN for test case '$caseName'."
    }

    $bootBin = Join-Path $outputDir "BOOT.BIN"
    $hash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash

    Write-Host "Smoke boot image ready for test case '$caseName':"
    Write-Host $bootBin
    Write-Host "SHA256: $hash"
}
