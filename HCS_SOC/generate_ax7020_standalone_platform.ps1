[CmdletBinding()]
param(
    [string]$XsctBat = "D:\VIVADO\Vitis\2023.1\bin\xsct.bat",
    [string]$XsaPath = "",
    [string]$WorkspaceRoot = "",
    [string]$PlatformName = "ax7020_udp_gateway_shadow_mirror_platform",
    [switch]$ForceRecreate
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($XsaPath)) {
    $XsaPath = Join-Path $workspace "udp_gateway_shadow_mirror_wrapper.xsa"
}
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Join-Path $workspace "ax7020_udp_gateway_shadow_mirror_platform_xsct\workspace"
}

function Resolve-ShadowApiBspRoot {
    param(
        [string]$WorkspaceRoot,
        [string]$PlatformName
    )

    $candidates = @(
        (Join-Path $WorkspaceRoot "$PlatformName\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0"),
        (Join-Path $WorkspaceRoot "standalone_bsp\ps7_cortexa9_0"),
        (Join-Path $WorkspaceRoot "$PlatformName\zynq_fsbl\zynq_fsbl_bsp\ps7_cortexa9_0")
    )

    foreach ($candidate in $candidates) {
        if ((Test-Path $candidate) -and (Test-Path (Join-Path $candidate "include\xparameters.h"))) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}

function Resolve-ShadowFsblBuildDir {
    param(
        [string]$WorkspaceRoot,
        [string]$PlatformName
    )

    $candidates = @(
        (Join-Path $WorkspaceRoot "$PlatformName\zynq_fsbl")
    )

    foreach ($candidate in $candidates) {
        if ((Test-Path $candidate) -and (Test-Path (Join-Path $candidate "Makefile"))) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}

function Resolve-WorkspaceFsblCandidate {
    param(
        [string]$WorkspaceRoot,
        [string]$PlatformName
    )

    $directCandidates = @(
        (Join-Path $WorkspaceRoot "$PlatformName\zynq_fsbl\fsbl.elf")
    )

    foreach ($candidate in $directCandidates) {
        if (Test-Path $candidate) {
            return (Get-Item $candidate)
        }
    }

    $direct = Get-ChildItem -Path $WorkspaceRoot -Recurse -File -Filter fsbl.elf -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -ne $direct) {
        return $direct
    }

    return Get-ChildItem -Path $WorkspaceRoot -Recurse -File -Include *fsbl*.elf -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Resolve-WorkspaceLwipLibrary {
    param([string]$WorkspaceRoot)

    return Get-ChildItem -Path $WorkspaceRoot -Recurse -File -Filter liblwip4.a -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Resolve-WorkspaceLibxil {
    param([string]$WorkspaceRoot)

    return Get-ChildItem -Path $WorkspaceRoot -Recurse -File -Filter libxil.a -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Resolve-ShadowGnuMakePath {
    param([string]$VitisRoot)

    $candidate = Join-Path $VitisRoot "gnuwin\bin\make.exe"
    if (Test-Path $candidate) {
        return (Resolve-Path $candidate).Path
    }

    $fallback = Get-Command make -ErrorAction SilentlyContinue
    if ($null -ne $fallback) {
        return $fallback.Source
    }

    throw "GNU make not found. Expected Vitis gnuwin make.exe under $VitisRoot"
}

function Resolve-ShadowGccBinDir {
    param([string]$VitisRoot)

    $candidate = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin"
    if (Test-Path $candidate) {
        return (Resolve-Path $candidate).Path
    }

    throw "arm-none-eabi GCC bin directory not found under $VitisRoot"
}

function Build-ShadowFsbl {
    param(
        [string]$FsblBuildDir,
        [string]$VitisRoot
    )

    $makeExe = Resolve-ShadowGnuMakePath -VitisRoot $VitisRoot
    $gccBinDir = Resolve-ShadowGccBinDir -VitisRoot $VitisRoot
    $originalPath = $env:PATH

    try {
        $env:PATH = "$gccBinDir;$(Split-Path -Parent $makeExe);$originalPath"
        Push-Location $FsblBuildDir

        foreach ($staleArtifact in @(
            (Join-Path $FsblBuildDir "fsbl.elf"),
            (Join-Path $FsblBuildDir "zynq_fsbl_bsp\ps7_cortexa9_0\lib\libxil.a")
        )) {
            if (Test-Path $staleArtifact) {
                Remove-Item -Force -LiteralPath $staleArtifact
            }
        }

        foreach ($stalePattern in @("*.o", "*.d")) {
            Get-ChildItem -Path $FsblBuildDir -File -Filter $stalePattern -ErrorAction SilentlyContinue |
                ForEach-Object {
                    Remove-Item -Force -LiteralPath $_.FullName
                }
        }

        & $makeExe
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to build generated FSBL under $FsblBuildDir"
        }
    }
    finally {
        Pop-Location
        $env:PATH = $originalPath
    }
}

function Convert-ToXsctPath {
    param([string]$Path)

    $resolved = (Resolve-Path $Path).Path
    if ($resolved -match '[^\u0000-\u007F]') {
        $shortPath = & cmd.exe /d /c ('for %I in ("{0}") do @echo %~sI' -f $resolved)
        if (($LASTEXITCODE -eq 0) -and (-not [string]::IsNullOrWhiteSpace($shortPath))) {
            $resolved = ($shortPath | Select-Object -Last 1).Trim()
        }
    }
    return ($resolved -replace "\\", "/")
}

foreach ($requiredPath in @($XsctBat, $XsaPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required shadow mirror platform input not found: $requiredPath"
    }
}

New-Item -ItemType Directory -Force -Path $WorkspaceRoot | Out-Null

if ($ForceRecreate) {
    foreach ($stale in @(
        (Join-Path $WorkspaceRoot $PlatformName),
        (Join-Path $WorkspaceRoot "standalone_bsp"),
        (Join-Path $WorkspaceRoot "zynq_fsbl")
    )) {
        if (Test-Path $stale) {
            Remove-Item -Recurse -Force $stale
        }
    }
}

$tclDir = Join-Path $WorkspaceRoot ".codex_xsct"
New-Item -ItemType Directory -Force -Path $tclDir | Out-Null
$tclPath = Join-Path $tclDir "generate_ax7020_standalone_platform.tcl"

$xsaPathUnix = Convert-ToXsctPath -Path $XsaPath
$workspaceUnix = Convert-ToXsctPath -Path $WorkspaceRoot
$platformNameEscaped = $PlatformName.Replace('"', '\"')
$vitisRoot = Split-Path -Parent (Split-Path -Parent (Resolve-Path $XsctBat).Path)

$tcl = @'
setws "{0}"
set xsa_path "{1}"
set platform_name "{2}"

set exit_code 0
if {{[catch {{
    if {{[file exists [file join "{0}" $platform_name]]}} {{
        file delete -force [file join "{0}" $platform_name]
    }}
    if {{[file exists [file join "{0}" "standalone_bsp"]]}} {{
        file delete -force [file join "{0}" "standalone_bsp"]
    }}
    if {{[file exists [file join "{0}" "zynq_fsbl"]]}} {{
        file delete -force [file join "{0}" "zynq_fsbl"]
    }}

    platform create -name $platform_name -hw $xsa_path -proc ps7_cortexa9_0 -os standalone
    platform active $platform_name
    platform generate
}} err opts]}} {{
    puts stderr $err
    set exit_code 1
}}
exit $exit_code
'@ -f $workspaceUnix, $xsaPathUnix, $platformNameEscaped
[System.IO.File]::WriteAllText($tclPath, $tcl, [System.Text.UTF8Encoding]::new($false))

Write-Host "Generating shadow mirror standalone platform workspace:"
Write-Host $WorkspaceRoot
Write-Host "Using XSA:"
Write-Host $XsaPath

& $XsctBat $tclPath
if ($LASTEXITCODE -ne 0) {
    throw "Shadow mirror standalone platform generation failed"
}

$apiBspRoot = Resolve-ShadowApiBspRoot -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
if ([string]::IsNullOrWhiteSpace($apiBspRoot)) {
    throw "Shadow mirror platform generation completed without an API BSP root containing include\\xparameters.h"
}

$fsblBuildDir = Resolve-ShadowFsblBuildDir -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
if ([string]::IsNullOrWhiteSpace($fsblBuildDir)) {
    throw "Shadow mirror platform generation completed without a generated zynq_fsbl Makefile under $WorkspaceRoot"
}
Build-ShadowFsbl -FsblBuildDir $fsblBuildDir -VitisRoot $vitisRoot

$libxil = Resolve-WorkspaceLibxil -WorkspaceRoot $WorkspaceRoot
if ($null -eq $libxil) {
    throw "Shadow mirror platform generation completed without libxil.a under $WorkspaceRoot"
}

$fsblCandidate = Resolve-WorkspaceFsblCandidate -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
if ($null -eq $fsblCandidate) {
    throw "Shadow mirror platform generation completed without an fsbl.elf candidate under $WorkspaceRoot"
}

$stagedFsblDir = Join-Path $WorkspaceRoot "$PlatformName\zynq_fsbl"
New-Item -ItemType Directory -Force -Path $stagedFsblDir | Out-Null
$stagedFsblPath = Join-Path $stagedFsblDir "fsbl.elf"
if ((Resolve-Path $fsblCandidate.FullName).Path -ne (Resolve-Path $stagedFsblPath -ErrorAction SilentlyContinue | ForEach-Object Path)) {
    Copy-Item -Path $fsblCandidate.FullName -Destination $stagedFsblPath -Force
}

Write-Host "Shadow mirror platform generation complete."
Write-Host "API BSP root: $apiBspRoot"
Write-Host "libxil: $($libxil.FullName)"
Write-Host "fsbl.elf: $stagedFsblPath"
