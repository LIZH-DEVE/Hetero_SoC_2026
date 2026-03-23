[CmdletBinding()]
param(
    [string]$XsctBat = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat",
    [string]$XsaPath = "",
    [string]$BitPath = ""
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($XsaPath)) {
    $XsaPath = Join-Path $workspace "system_wrapper.xsa"
}
if ([string]::IsNullOrWhiteSpace($BitPath)) {
    $BitPath = Join-Path $workspace "HCS_SOC.runs\impl_1\system_wrapper.bit"
}

$platformRoot = Join-Path $workspace "platform"
$platformExportRoot = Join-Path $platformRoot "export\platform"
$platformHwRoot = Join-Path $platformRoot "hw"
$exportHwRoot = Join-Path $platformExportRoot "hw"
$exportHwSdtRoot = Join-Path $exportHwRoot "sdt"
$exportSwIncludeRoot = Join-Path $platformExportRoot "sw\standalone_ps7_cortexa9_0\include"
$localBspIncludeRoot = Join-Path $platformRoot "ps7_cortexa9_0\standalone_ps7_cortexa9_0\bsp\include"
$vitisCompJson = Join-Path $platformRoot "vitis-comp.json"
$platformXpfm = Join-Path $platformExportRoot "platform.xpfm"
$backupRoot = Join-Path $platformRoot ("sync_backup_" + (Get-Date -Format "yyyyMMdd_HHmmss"))

if (-not (Test-Path $XsctBat)) {
    throw "xsct.bat not found: $XsctBat"
}
if (-not (Test-Path $XsaPath)) {
    throw "system_wrapper.xsa not found: $XsaPath"
}
if (-not (Test-Path $BitPath)) {
    throw "system_wrapper.bit not found: $BitPath"
}
if (-not (Test-Path $vitisCompJson)) {
    throw "vitis-comp.json not found: $vitisCompJson"
}
if (-not (Test-Path $platformXpfm)) {
    throw "platform.xpfm not found: $platformXpfm"
}
if (-not (Test-Path $exportSwIncludeRoot)) {
    throw "platform BSP include dir not found: $exportSwIncludeRoot"
}
if (-not (Test-Path $localBspIncludeRoot)) {
    throw "local BSP include dir not found: $localBspIncludeRoot"
}

New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

function Backup-IfExists {
    param([string]$PathValue)
    if (Test-Path $PathValue) {
        $target = Join-Path $backupRoot ([IO.Path]::GetFileName($PathValue))
        Copy-Item -Path $PathValue -Destination $target -Force
    }
}

function Force-Gem0RgmiiArtifacts {
    param([string[]]$TargetFiles)

    foreach ($file in $TargetFiles) {
        if (-not (Test-Path $file)) {
            continue
        }

        $text = Get-Content -Raw $file
        $updated = $text

        $updated = $updated -replace 'phy-mode\s*=\s*"gmii";', 'phy-mode = "rgmii-id";'
        $updated = $updated -replace 'xlnx,eth-mode\s*=\s*<0>;', 'xlnx,eth-mode = <1>;'
        $updated = $updated -replace 'xlnx,eth-mode\s*=\s*<0x0>;', 'xlnx,eth-mode = <0x1>;'
        $updated = $updated -replace '"gmii"\s*/\*\s*phy-mode\s*\*/', '"rgmii-id" /* phy-mode */'

        if ($updated -ne $text) {
            Set-Content -Path $file -Value $updated -Encoding UTF8
            Write-Host "Patched GEM0 phy-mode to RGMII in $file"
        }
    }
}

Backup-IfExists $vitisCompJson
Backup-IfExists $platformXpfm
Backup-IfExists (Join-Path $platformHwRoot "system_wrapper.xsa")
Backup-IfExists (Join-Path $platformHwRoot "system_wrapper.bit")
Backup-IfExists (Join-Path $exportHwRoot "system_wrapper.xsa")
Backup-IfExists (Join-Path $exportHwRoot "system_wrapper.bit")
Backup-IfExists (Join-Path $exportSwIncludeRoot "xparameters.h")
Backup-IfExists (Join-Path $localBspIncludeRoot "xparameters.h")
Backup-IfExists (Join-Path $exportHwRoot "ps7_init.tcl")
Backup-IfExists (Join-Path $exportHwSdtRoot "ps7_init.tcl")
Backup-IfExists (Join-Path $exportHwSdtRoot "pcw.dtsi")
Backup-IfExists (Join-Path $platformExportRoot "sw\standalone_ps7_cortexa9_0\hw_artifacts\ps7_cortexa9_0_baremetal.dts")
Backup-IfExists (Join-Path $platformRoot "ps7_cortexa9_0\standalone_ps7_cortexa9_0\bsp\libsrc\emacps\src\xemacps_g.c")

$extractDir = Join-Path $env:TEMP ("system_wrapper_extract_" + [Guid]::NewGuid().ToString("N"))
$bspDir = Join-Path $env:TEMP ("system_wrapper_bsp_" + [Guid]::NewGuid().ToString("N"))
$hsiTcl = Join-Path $env:TEMP ("system_wrapper_bsp_" + [Guid]::NewGuid().ToString("N") + ".tcl")

try {
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    New-Item -ItemType Directory -Force -Path $bspDir | Out-Null

    tar -xf $XsaPath -C $extractDir

    @"
hsi open_hw_design {$($XsaPath -replace '\\','/')}
hsi create_sw_design temp_sw -proc ps7_cortexa9_0 -os standalone
hsi generate_bsp -sw temp_sw -dir {$($bspDir -replace '\\','/')}
puts "BSP generation done"
exit
"@ | Set-Content -Path $hsiTcl -Encoding ASCII

    & $XsctBat $hsiTcl
    if ($LASTEXITCODE -ne 0) {
        throw "XSCT BSP generation failed with exit code $LASTEXITCODE"
    }

    $newXparams = Join-Path $bspDir "ps7_cortexa9_0\include\xparameters.h"
    if (-not (Test-Path $newXparams)) {
        throw "generated xparameters.h not found: $newXparams"
    }

    foreach ($dir in @($platformHwRoot, $exportHwRoot, $exportHwSdtRoot)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    Copy-Item -Path $XsaPath -Destination (Join-Path $platformHwRoot "system_wrapper.xsa") -Force
    Copy-Item -Path $XsaPath -Destination (Join-Path $exportHwRoot "system_wrapper.xsa") -Force
    Copy-Item -Path $BitPath -Destination (Join-Path $platformHwRoot "system_wrapper.bit") -Force
    Copy-Item -Path $BitPath -Destination (Join-Path $exportHwRoot "system_wrapper.bit") -Force

    foreach ($name in @("ps7_init.c", "ps7_init.h", "ps7_init.html", "ps7_init.tcl", "ps7_init_gpl.c", "ps7_init_gpl.h")) {
        $src = Join-Path $extractDir $name
        if (Test-Path $src) {
            Copy-Item -Path $src -Destination (Join-Path $exportHwRoot $name) -Force
            Copy-Item -Path $src -Destination (Join-Path $exportHwSdtRoot $name) -Force
        }
    }

    Copy-Item -Path $newXparams -Destination (Join-Path $exportSwIncludeRoot "xparameters.h") -Force
    Copy-Item -Path $newXparams -Destination (Join-Path $localBspIncludeRoot "xparameters.h") -Force

    Force-Gem0RgmiiArtifacts @(
        (Join-Path $exportHwSdtRoot "pcw.dtsi"),
        (Join-Path $platformExportRoot "sw\standalone_ps7_cortexa9_0\hw_artifacts\ps7_cortexa9_0_baremetal.dts"),
        (Join-Path $platformRoot "ps7_cortexa9_0\standalone_ps7_cortexa9_0\bsp\libsrc\emacps\src\xemacps_g.c")
    )

    $json = Get-Content -Raw $vitisCompJson | ConvertFrom-Json
    $json.configuration.xsa = $XsaPath
    $json.configuration.xsaPathInPlatform = "platform\\hw\\system_wrapper.xsa"
    ($json | ConvertTo-Json -Depth 32) | Set-Content -Path $vitisCompJson -Encoding UTF8

    $xpfmText = Get-Content -Raw $platformXpfm
    $xpfmText = $xpfmText -replace 'sdx:name="design_1_wrapper\.xsa"', 'sdx:name="system_wrapper.xsa"'
    Set-Content -Path $platformXpfm -Value $xpfmText -Encoding UTF8

    Write-Host "Platform synchronized to system_wrapper."
    Write-Host "Backup dir: $backupRoot"
    Write-Host "XSA: $XsaPath"
    Write-Host "BIT: $BitPath"
    Write-Host "xparameters.h updated in export and local BSP include trees."
}
finally {
    Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $bspDir -ErrorAction SilentlyContinue
    Remove-Item -Force $hsiTcl -ErrorAction SilentlyContinue
}
