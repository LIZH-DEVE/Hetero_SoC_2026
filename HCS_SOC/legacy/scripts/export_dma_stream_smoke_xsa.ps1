[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$XsaPath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$exportTcl = Join-Path $workspace "export_dma_stream_smoke_xsa.tcl"
if ([string]::IsNullOrWhiteSpace($XsaPath)) {
    $XsaPath = Join-Path $workspace "stream_smoke_dma_wrapper.xsa"
}

foreach ($pathInfo in @(
    @{ Label = "vivado.bat"; Path = $VivadoBat },
    @{ Label = "export_dma_stream_smoke_xsa.tcl"; Path = $exportTcl }
)) {
    if (-not (Test-Path $pathInfo.Path)) {
        throw "$($pathInfo.Label) not found: $($pathInfo.Path)"
    }
}

if ($DryRun) {
    $oldDryRun = $env:STREAM_SMOKE_EXPORT_DRY_RUN
    $env:STREAM_SMOKE_EXPORT_DRY_RUN = "1"
} else {
    $oldDryRun = $null
    Remove-Item Env:STREAM_SMOKE_EXPORT_DRY_RUN -ErrorAction SilentlyContinue
}

try {
    & $VivadoBat -mode batch -source $exportTcl
}
finally {
    if ($null -ne $oldDryRun) {
        $env:STREAM_SMOKE_EXPORT_DRY_RUN = $oldDryRun
    } else {
        Remove-Item Env:STREAM_SMOKE_EXPORT_DRY_RUN -ErrorAction SilentlyContinue
    }
}
if ($LASTEXITCODE -ne 0) {
    throw "Vivado stream-smoke XSA export failed with exit code $LASTEXITCODE"
}

if ($DryRun) {
    Write-Host "Dry-run completed for stream-smoke XSA export."
    Write-Host "Expected XSA on full run:"
    Write-Host $XsaPath
    exit 0
}

for ($attempt = 0; $attempt -lt 10; $attempt++) {
    if (Test-Path $XsaPath) {
        break
    }
    Start-Sleep -Seconds 2
}

if (-not (Test-Path $XsaPath)) {
    throw "stream_smoke_dma_wrapper.xsa was not generated: $XsaPath"
}

Write-Host "Exported fresh stream_smoke_dma_wrapper XSA:"
Write-Host $XsaPath
