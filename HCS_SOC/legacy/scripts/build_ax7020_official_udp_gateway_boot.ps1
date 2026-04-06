[CmdletBinding()]
param(
    [string]$BootgenPath,
    [string]$FsblElf = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\platform\export\platform\sw\boot\fsbl.elf",
    [string]$Bitstream = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\platform\export\platform\hw\system_wrapper.bit",
    [string]$AppElf = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_official_net_test_app\manual_build\ax7020_official_net_test_app.elf",
    [string]$OutputDir = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_udp_crypto_gateway_system"
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
    throw "Failed to package official UDP gateway BOOT.BIN."
}

Write-Host "Official UDP gateway boot image ready:"
Write-Host (Join-Path $OutputDir "BOOT.BIN")
