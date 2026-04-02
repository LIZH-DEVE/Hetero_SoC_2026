[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$XsaPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$tcl = Join-Path $workspace "export_dma_gateway_hybrid_xsa.tcl"

if ([string]::IsNullOrWhiteSpace($XsaPath)) {
    $XsaPath = Join-Path $workspace "dma_gateway_hybrid_wrapper.xsa"
}

if (-not (Test-Path $VivadoBat)) {
    throw "Vivado not found: $VivadoBat"
}
if (-not (Test-Path $tcl)) {
    throw "Hybrid export Tcl not found: $tcl"
}

& $VivadoBat -mode batch -source $tcl
if ($LASTEXITCODE -ne 0) {
    throw "export_dma_gateway_hybrid_xsa.tcl failed"
}

if (($env:DMA_GATEWAY_HYBRID_EXPORT_DRY_RUN -eq "1") -and (-not (Test-Path $XsaPath))) {
    Write-Host "Hybrid export dry-run completed without generating an XSA."
    exit 0
}

if (-not (Test-Path $XsaPath)) {
    throw "Hybrid XSA was not generated: $XsaPath"
}

Write-Host "Exported hybrid XSA:"
Write-Host $XsaPath
