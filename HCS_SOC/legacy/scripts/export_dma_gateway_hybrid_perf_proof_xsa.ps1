[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$XsaPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$tcl = Join-Path $workspace "export_dma_gateway_hybrid_perf_proof_xsa.tcl"

if ([string]::IsNullOrWhiteSpace($XsaPath)) {
    $XsaPath = Join-Path $workspace "dma_gateway_hybrid_perf_proof_wrapper.xsa"
}

if (-not (Test-Path $VivadoBat)) {
    throw "Vivado not found: $VivadoBat"
}
if (-not (Test-Path $tcl)) {
    throw "Hybrid perf proof export Tcl not found: $tcl"
}

& $VivadoBat -mode batch -source $tcl
if ($LASTEXITCODE -ne 0) {
    throw "export_dma_gateway_hybrid_perf_proof_xsa.tcl failed"
}

if (($env:DMA_GATEWAY_HYBRID_PERF_PROOF_EXPORT_DRY_RUN -eq "1") -and (-not (Test-Path $XsaPath))) {
    Write-Host "Hybrid perf proof export dry-run completed without generating an XSA."
    exit 0
}

if (-not (Test-Path $XsaPath)) {
    throw "Hybrid perf proof XSA was not generated: $XsaPath"
}

Write-Host "Exported hybrid perf proof XSA:"
Write-Host $XsaPath
