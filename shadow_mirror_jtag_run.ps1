$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$delegate = Join-Path $workspace "HCS_SOC\shadow_mirror_jtag_run.ps1"

if (-not (Test-Path $delegate)) {
    throw "Delegate JTAG runner not found: $delegate"
}

& $delegate @args
