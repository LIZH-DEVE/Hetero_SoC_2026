[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[A-Za-z]$")]
    [string]$DriveLetter,

    [string]$BootBin = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_official_udp_crypto_gateway\BOOT.BIN"
)

$ErrorActionPreference = "Stop"

$driveRoot = "{0}:\" -f $DriveLetter.ToUpperInvariant()
if (-not (Test-Path $driveRoot)) {
    throw "Drive not found: $driveRoot"
}

if (-not (Test-Path $BootBin)) {
    throw "BOOT.BIN not found: $BootBin"
}

$dest = Join-Path $driveRoot "BOOT.BIN"
Copy-Item $BootBin $dest -Force
Write-Host "Deployed BOOT.BIN to $dest"
Get-FileHash $dest -Algorithm SHA256 | Format-Table -Auto
