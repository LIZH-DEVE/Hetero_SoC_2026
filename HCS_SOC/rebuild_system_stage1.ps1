[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [ValidateRange(1,8)]
    [int]$CryptoInstances = 2
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$tcl = Join-Path $workspace "rebuild_system_stage1.tcl"

if (-not (Test-Path $VivadoBat)) {
    throw "vivado.bat not found: $VivadoBat"
}
if (-not (Test-Path $tcl)) {
    throw "tcl not found: $tcl"
}

Write-Host "Running Vivado Stage1 rebuild..."
Write-Host "CRYPTO_NUM_INSTANCES=$CryptoInstances"
$oldCryptoEnv = $env:CRYPTO_NUM_INSTANCES
$env:CRYPTO_NUM_INSTANCES = "$CryptoInstances"
try {
    & $VivadoBat -mode batch -source $tcl
}
finally {
    $env:CRYPTO_NUM_INSTANCES = $oldCryptoEnv
}
if ($LASTEXITCODE -ne 0) {
    throw "Vivado rebuild failed with exit code $LASTEXITCODE"
}

Write-Host "Stage1 rebuild completed."
Write-Host "Expected bit: $(Join-Path $workspace 'HCS_SOC.runs\impl_1\system_wrapper.bit')"
Write-Host "Expected xsa: $(Join-Path $workspace 'system_wrapper.xsa')"
