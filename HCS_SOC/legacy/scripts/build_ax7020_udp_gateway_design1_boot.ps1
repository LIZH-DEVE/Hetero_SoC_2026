[CmdletBinding()]
param(
    [string]$BootgenPath,
    [string]$FsblElf = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\vitis_2023_udp_gateway_ws_design1\ax7020_udp_gateway_platform_design1\zynq_fsbl\fsbl.elf",
    [string]$Bitstream = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\platform\export\platform\hw\design_1_wrapper.bit",
    [string]$AppElf = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_official_net_test_app\manual_build_design1\ax7020_udp_gateway_design1_app.elf",
    [string]$OutputDir = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_udp_gateway_design1_system"
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
    throw "Failed to package design1 UDP gateway BOOT.BIN."
}

Write-Host "Design1 UDP gateway boot image ready:"
Write-Host (Join-Path $OutputDir "BOOT.BIN")
