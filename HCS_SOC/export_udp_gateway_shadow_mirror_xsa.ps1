[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$XsaPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$tcl = Join-Path $workspace "export_udp_gateway_shadow_mirror_xsa.tcl"
$projectFile = Join-Path $workspace "HCS_SOC.xpr"
$projectLock = Join-Path $workspace ".lock"

function Repair-ShadowMirrorProjectTop {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath
    )

    if (-not (Test-Path $ProjectPath)) {
        throw "Shadow mirror project file not found: $ProjectPath"
    }

    $text = Get-Content -Path $ProjectPath -Raw -Encoding UTF8
    $updated = $text

    $updated = [regex]::Replace(
        $updated,
        '(<FileSet Name="sources_1"[\s\S]*?<Option Name="TopModule" Val=")[^"]+(")',
        '${1}udp_gateway_shadow_mirror_wrapper$2',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    if ($updated -match '<FileSet Name="sources_1"[\s\S]*?<Option Name="TopAutoSet" Val="') {
        $updated = [regex]::Replace(
            $updated,
            '(<FileSet Name="sources_1"[\s\S]*?<Option Name="TopAutoSet" Val=")[^"]+(")',
            '${1}FALSE$2',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
    } else {
        $updated = [regex]::Replace(
            $updated,
            '(<FileSet Name="sources_1"[\s\S]*?<Option Name="TopModule" Val="udp_gateway_shadow_mirror_wrapper"/>\r?\n)(\s*</Config>)',
            "`$1        <Option Name=`"TopAutoSet`" Val=`"FALSE`"/>`r`n`$2",
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
    }

    if ($updated -ne $text) {
        Set-Content -Path $ProjectPath -Value $updated -Encoding UTF8
    }
}

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

Repair-ShadowMirrorProjectTop -ProjectPath $projectFile
Remove-StaleShadowMirrorProjectLock -LockPath $projectLock

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
