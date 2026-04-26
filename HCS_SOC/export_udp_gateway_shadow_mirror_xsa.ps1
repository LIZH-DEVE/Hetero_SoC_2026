[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$XsaPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$tcl = Join-Path $workspace "export_udp_gateway_shadow_mirror_xsa.tcl"
$projectLock = Join-Path $workspace ".lock"

function Remove-StaleShadowMirrorProjectLock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LockPath
    )

    if (-not (Test-Path $LockPath)) {
        return
    }

    $runningVivado = @(Get-Process -Name vivado -ErrorAction SilentlyContinue)
    if ($runningVivado.Count -ne 0) {
        return
    }

    Remove-Item -LiteralPath $LockPath -Force
}

if ([string]::IsNullOrWhiteSpace($XsaPath)) {
    $XsaPath = Join-Path $workspace "udp_gateway_shadow_mirror_wrapper.xsa"
}

if (-not (Test-Path $VivadoBat)) {
    throw "Vivado not found: $VivadoBat"
}
if (-not (Test-Path $tcl)) {
    throw "Shadow mirror export Tcl not found: $tcl"
}

Remove-StaleShadowMirrorProjectLock -LockPath $projectLock

if (-not $env:UDP_GATEWAY_SHADOW_MIRROR_DIRECT_SCRIPT_FLOW) {
    $env:UDP_GATEWAY_SHADOW_MIRROR_DIRECT_SCRIPT_FLOW = "0"
}

& $VivadoBat -mode batch -source $tcl
if ($LASTEXITCODE -ne 0) {
    throw "export_udp_gateway_shadow_mirror_xsa.tcl failed"
}

if (($env:UDP_GATEWAY_SHADOW_MIRROR_EXPORT_DRY_RUN -eq "1") -and (-not (Test-Path $XsaPath))) {
    Write-Host "Shadow mirror export dry-run completed without generating an XSA."
    exit 0
}

if (-not (Test-Path $XsaPath)) {
    throw "Shadow mirror XSA was not generated: $XsaPath"
}

Write-Host "Exported shadow mirror XSA:"
Write-Host $XsaPath
