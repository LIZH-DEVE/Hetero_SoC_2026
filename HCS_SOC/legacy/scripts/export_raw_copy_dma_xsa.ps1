[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$XsaPath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$exportTcl = Join-Path $workspace "export_raw_copy_dma_xsa.tcl"
if ([string]::IsNullOrWhiteSpace($XsaPath)) {
    $XsaPath = Join-Path $workspace "raw_copy_dma_wrapper.xsa"
}

foreach ($pathInfo in @(
    @{ Label = "vivado.bat"; Path = $VivadoBat },
    @{ Label = "export_raw_copy_dma_xsa.tcl"; Path = $exportTcl }
)) {
    if (-not (Test-Path $pathInfo.Path)) {
        throw "$($pathInfo.Label) not found: $($pathInfo.Path)"
    }
}

if ($DryRun) {
    $oldDryRun = $env:RAW_COPY_EXPORT_DRY_RUN
    $env:RAW_COPY_EXPORT_DRY_RUN = "1"
} else {
    $oldDryRun = $null
    Remove-Item Env:RAW_COPY_EXPORT_DRY_RUN -ErrorAction SilentlyContinue
}

try {
    & $VivadoBat -mode batch -source $exportTcl
}
finally {
    if ($null -ne $oldDryRun) {
        $env:RAW_COPY_EXPORT_DRY_RUN = $oldDryRun
    } else {
        Remove-Item Env:RAW_COPY_EXPORT_DRY_RUN -ErrorAction SilentlyContinue
    }
}
if ($LASTEXITCODE -ne 0) {
    throw "Vivado raw-copy XSA export failed with exit code $LASTEXITCODE"
}

if ($DryRun) {
    Write-Host "Dry-run completed for raw-copy XSA export."
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
    throw "raw_copy_dma_wrapper.xsa was not generated: $XsaPath"
}

Write-Host "Exported fresh raw_copy_dma_wrapper XSA:"
Write-Host $XsaPath
