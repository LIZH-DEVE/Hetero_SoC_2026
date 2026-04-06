[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat"
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$exportTcl = Join-Path $workspace "export_xsa.tcl"
$xsaPath = Join-Path $workspace "design_1_wrapper.xsa"

foreach ($pathInfo in @(
    @{ Label = "vivado.bat"; Path = $VivadoBat },
    @{ Label = "export_xsa.tcl"; Path = $exportTcl }
)) {
    if (-not (Test-Path $pathInfo.Path)) {
        throw "$($pathInfo.Label) not found: $($pathInfo.Path)"
    }
}

& $VivadoBat -mode batch -source $exportTcl
if ($LASTEXITCODE -ne 0) {
    throw "Vivado design_1 XSA export failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path $xsaPath)) {
    throw "design_1_wrapper.xsa was not generated: $xsaPath"
}

Write-Host "Exported fresh design_1_wrapper XSA:"
Write-Host $xsaPath
