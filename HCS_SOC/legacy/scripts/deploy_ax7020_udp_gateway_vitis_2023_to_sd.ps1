param(
    [string]$DriveLetter = "E"
)

$ErrorActionPreference = "Stop"

$bootBin = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\vitis_2023_udp_gateway_ws_2\ax7020_udp_gateway_app_system\Debug\sd_card\BOOT.BIN"
$targetRoot = "$DriveLetter`:\"
$targetBoot = Join-Path $targetRoot "BOOT.BIN"

if (-not (Test-Path $bootBin)) {
    throw "BOOT.BIN not found: $bootBin"
}

if (-not (Test-Path $targetRoot)) {
    throw "Target drive not ready: $targetRoot"
}

Copy-Item $bootBin $targetBoot -Force

$srcHash = (Get-FileHash $bootBin -Algorithm SHA256).Hash
$dstHash = (Get-FileHash $targetBoot -Algorithm SHA256).Hash

Write-Host "Source: $bootBin"
Write-Host "Target: $targetBoot"
Write-Host "Source SHA256: $srcHash"
Write-Host "Target SHA256: $dstHash"

if ($srcHash -ne $dstHash) {
    throw "SHA256 mismatch after copy"
}

Write-Host "DEPLOY_OK"
