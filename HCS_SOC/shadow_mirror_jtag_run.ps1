$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$delegate = Join-Path $workspace "run_ax7020_udp_gateway_shadow_mirror_jtag.ps1"

if (-not (Test-Path $delegate)) {
    throw "Delegate JTAG runner not found: $delegate"
}

& $delegate @args
