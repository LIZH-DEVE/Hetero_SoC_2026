[CmdletBinding()]
param(
    [string]$BootgenPath,
    [string]$FsblElf = "D:\FPGAhanjia\Hetero_SoC_2026_3\AX7020_2023.1\course_s2_vitis\06_net_test\Vitis\design_1_wrapper\zynq_fsbl\fsbl.elf",
    [string]$Bitstream = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\platform\export\platform\hw\design_1_wrapper.bit",
    [string]$AppElf = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\vitis_2023_udp_gateway_ws_2\ax7020_udp_gateway_app\Debug\ax7020_udp_gateway_app.elf",
    [string]$OutputDir = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_udp_gateway_design1_hybrid_official_fsbl_ws2app"
)

$ErrorActionPreference = "Stop"

$buildBootScript = Join-Path $PSScriptRoot "build_boot_bin.ps1"
if (-not (Test-Path $buildBootScript)) {
    throw "build_boot_bin.ps1 not found: $buildBootScript"
}

& $buildBootScript `
    -BootgenPath $BootgenPath `
    -FsblElf $FsblElf `
    -Bitstream $Bitstream `
    -AppElf $AppElf `
    -OutputDir $OutputDir

if ($LASTEXITCODE -ne 0) {
    throw "Failed to package design1 hybrid official-FSBL ws2-app BOOT.BIN."
}

Write-Host "Design1 hybrid official-FSBL ws2-app boot image ready:"
Write-Host (Join-Path $OutputDir "BOOT.BIN")
