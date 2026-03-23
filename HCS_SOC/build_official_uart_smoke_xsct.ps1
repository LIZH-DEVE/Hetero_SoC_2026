[CmdletBinding()]
param(
    [string]$XsctPath = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat"
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$tclScript = Join-Path $workspace "build_official_uart_smoke_xsct.tcl"

if (-not (Test-Path $XsctPath)) {
    throw "xsct not found: $XsctPath"
}

if (-not (Test-Path $tclScript)) {
    throw "Tcl script not found: $tclScript"
}

& $XsctPath $tclScript
if ($LASTEXITCODE -ne 0) {
    throw "xsct build failed."
}
