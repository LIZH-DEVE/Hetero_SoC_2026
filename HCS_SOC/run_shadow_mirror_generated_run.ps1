[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RunDir,
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$LogName = "",
    [string]$MessageDbName = "vivado_manual.pb"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path $VivadoBat)) {
    throw "Vivado not found: $VivadoBat"
}

$resolvedRunDir = (Resolve-Path $RunDir).Path
$runTcls = @(Get-ChildItem -LiteralPath $resolvedRunDir -Filter *.tcl -File | Select-Object -ExpandProperty Name)
if ($runTcls.Count -ne 1) {
    throw "Expected exactly one run Tcl in $resolvedRunDir, got $($runTcls.Count)"
}

$runTcl = $runTcls[0]
if ([string]::IsNullOrWhiteSpace($LogName)) {
    $LogName = ([System.IO.Path]::GetFileNameWithoutExtension($runTcl) + "_manual.vds")
}

Push-Location $resolvedRunDir
try {
    Remove-Item -LiteralPath $LogName, $MessageDbName -Force -ErrorAction SilentlyContinue
    & $VivadoBat -log $LogName -product Vivado -mode batch -messageDb $MessageDbName -notrace -source $runTcl
    if ($LASTEXITCODE -ne 0) {
        throw "Generated run failed: $resolvedRunDir"
    }
}
finally {
    Pop-Location
}
