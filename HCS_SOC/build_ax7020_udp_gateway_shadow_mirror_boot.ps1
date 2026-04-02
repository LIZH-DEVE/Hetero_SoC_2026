[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$VitisRoot = "D:\Xilinx\Vitis\2024.1",
    [string]$XsctBat = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat",
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
    [string]$XsaPath = "",
    [string]$WorkspaceRoot = "",
    [string]$PlatformName = "ax7020_udp_gateway_shadow_mirror_platform",
    [string]$OutputDir = "",
    [switch]$ForceExport
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$exportXsaScript = Join-Path $workspace "export_udp_gateway_shadow_mirror_xsa.ps1"
$platformScript = Join-Path $workspace "generate_ax7020_standalone_platform.ps1"
$appBuildScript = Join-Path $workspace "build_ax7020_udp_gateway_shadow_mirror_app.ps1"
$bootBuildScript = Join-Path $workspace "build_boot_bin.ps1"
$releaseDir = Join-Path $workspace "sd_boot\ax7020_udp_gateway_shadow_mirror"
$readmePath = Join-Path $releaseDir "readme.txt"
$appElf = Join-Path $workspace "ax7020_udp_gateway_shadow_mirror_app\build\ax7020_udp_gateway_shadow_mirror_app.elf"

if ([string]::IsNullOrWhiteSpace($XsaPath)) {
    $XsaPath = Join-Path $workspace "udp_gateway_shadow_mirror_wrapper.xsa"
}
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Join-Path $workspace "ax7020_udp_gateway_shadow_mirror_platform_xsct\workspace"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = $releaseDir
}

function Resolve-ShadowApiBspRoot {
    param(
        [string]$WorkspaceRoot,
        [string]$PlatformName
    )

    $candidates = @(
        (Join-Path $WorkspaceRoot "$PlatformName\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0"),
        (Join-Path $WorkspaceRoot "standalone_bsp\ps7_cortexa9_0")
    )

    foreach ($candidate in $candidates) {
        if ((Test-Path $candidate) -and (Test-Path (Join-Path $candidate "include\xparameters.h"))) {
            return $candidate
        }
    }

    throw "Shadow mirror platform API BSP root not found under $WorkspaceRoot"
}

function Resolve-ShadowFsblElf {
    param(
        [string]$WorkspaceRoot,
        [string]$PlatformName
    )

    $candidates = @(
        (Join-Path $WorkspaceRoot "$PlatformName\zynq_fsbl\fsbl.elf"),
        (Join-Path $WorkspaceRoot "$PlatformName\export\$PlatformName\sw\$PlatformName\boot\fsbl.elf")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Get-Item $candidate)
        }
    }

    return Get-ChildItem -Path $WorkspaceRoot -Recurse -File -Filter fsbl.elf -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Resolve-BootgenExecutable {
    param([string]$ConfiguredPath)

    $candidates = @($ConfiguredPath, "D:\Xilinx\Vivado\2023.1\bin\bootgen.bat", "C:\Xilinx\Vivado\2023.1\bin\bootgen.bat")
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "bootgen was not found. Pass -BootgenPath explicitly."
}

foreach ($requiredPath in @($exportXsaScript, $platformScript, $appBuildScript, $bootBuildScript, $XsctBat)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required shadow mirror build input not found: $requiredPath"
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
foreach ($staleArtifact in @(
    "BOOT.BIN",
    "fsbl.elf",
    "udp_gateway_shadow_mirror_wrapper.bit",
    "ax7020_udp_gateway_shadow_mirror_app.elf",
    "boot.bif",
    "bootgen_read.txt",
    "readme.txt"
)) {
    $stalePath = Join-Path $OutputDir $staleArtifact
    if (Test-Path $stalePath) {
        Remove-Item -Force -LiteralPath $stalePath
    }
}

$workspaceParent = Split-Path -Parent $WorkspaceRoot
$xsaExtractDir = Join-Path $workspaceParent "xsa_extract"

if ($ForceExport -and (Test-Path $XsaPath)) {
    Write-Host "ForceExport enabled. Regenerating shadow mirror XSA:"
    Write-Host $XsaPath
    & $exportXsaScript -VivadoBat $VivadoBat -XsaPath $XsaPath
    if ($LASTEXITCODE -ne 0) {
        throw "Shadow mirror XSA export failed"
    }
    if (-not (Test-Path $XsaPath)) {
        throw "Shadow mirror XSA export returned without generating $XsaPath"
    }
} elseif (-not (Test-Path $XsaPath)) {
    if (Test-Path Env:\UDP_GATEWAY_SHADOW_MIRROR_EXPORT_DRY_RUN) {
        Remove-Item Env:\UDP_GATEWAY_SHADOW_MIRROR_EXPORT_DRY_RUN
    }
    & $exportXsaScript -VivadoBat $VivadoBat -XsaPath $XsaPath
    if ($LASTEXITCODE -ne 0) {
        throw "Shadow mirror XSA export failed"
    }
    if (-not (Test-Path $XsaPath)) {
        throw "Shadow mirror XSA export returned without generating $XsaPath"
    }
} else {
    Write-Host "Reusing existing shadow mirror XSA:"
    Write-Host $XsaPath
}

try {
    $platformSwDir = Resolve-ShadowApiBspRoot -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
    $fsblElf = Resolve-ShadowFsblElf -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
    if ($null -eq $fsblElf) {
        throw "fresh fsbl.elf missing"
    }
    Write-Host "Reusing existing shadow mirror platform workspace:"
    Write-Host $WorkspaceRoot
} catch {
    & $platformScript -XsctBat $XsctBat -XsaPath $XsaPath -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
    if ($LASTEXITCODE -ne 0) {
        throw "Shadow mirror platform generation failed"
    }

    $platformSwDir = Resolve-ShadowApiBspRoot -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
    $fsblElf = Resolve-ShadowFsblElf -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
    if ($null -eq $fsblElf) {
        throw "Fresh shadow mirror fsbl.elf not found under $WorkspaceRoot"
    }
}

& $appBuildScript -VitisRoot $VitisRoot -PlatformSwDir $platformSwDir
if ($LASTEXITCODE -ne 0) {
    throw "Shadow mirror app build failed"
}

if (-not (Test-Path $appElf)) {
    throw "Shadow mirror app ELF not found: $appElf"
}

if (Test-Path $xsaExtractDir) {
    Remove-Item -Recurse -Force $xsaExtractDir
}
New-Item -ItemType Directory -Force -Path $xsaExtractDir | Out-Null

tar -xf $XsaPath -C $xsaExtractDir
if ($LASTEXITCODE -ne 0) {
    throw "Failed to extract shadow mirror XSA: $XsaPath"
}

$bitstream = Get-ChildItem -Path $xsaExtractDir -File -Filter *.bit |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $bitstream) {
    throw "No bitstream found inside shadow mirror XSA: $XsaPath"
}

$stagedFsbl = Join-Path $OutputDir "fsbl.elf"
$stagedBit = Join-Path $OutputDir "udp_gateway_shadow_mirror_wrapper.bit"
$stagedApp = Join-Path $OutputDir "ax7020_udp_gateway_shadow_mirror_app.elf"

Copy-Item -Path $fsblElf.FullName -Destination $stagedFsbl -Force
Copy-Item -Path $bitstream.FullName -Destination $stagedBit -Force
Copy-Item -Path $appElf -Destination $stagedApp -Force

& $bootBuildScript `
    -BootgenPath $BootgenPath `
    -FsblElf $stagedFsbl `
    -Bitstream $stagedBit `
    -AppElf $stagedApp `
    -OutputDir $OutputDir

if ($LASTEXITCODE -ne 0) {
    throw "Failed to package shadow mirror BOOT.BIN"
}

$bootBin = Join-Path $OutputDir "BOOT.BIN"
if (-not (Test-Path $bootBin)) {
    throw "Shadow mirror BOOT.BIN not found after packaging: $bootBin"
}

$bootgen = Resolve-BootgenExecutable -ConfiguredPath $BootgenPath
$bootReadPath = Join-Path $OutputDir "bootgen_read.txt"
$bootRead = & $bootgen -read $bootBin 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "bootgen -read failed for shadow mirror BOOT.BIN"
}
Set-Content -Path $bootReadPath -Value $bootRead -Encoding ASCII

$bootHash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash

$readme = @(
    "UDP gateway shadow mirror image",
    "",
    "Purpose:",
    "- Phase C shadow mirror app for the combined live direct crypto + hybrid DMA shadow hardware line.",
    "- Confirms live gateway control flow remains intact.",
    "- Confirms the PS mirror shadow path uses deep-copy payload isolation and sticky halt on timeout.",
    "- This is not a live cutover image.",
    "",
    "Expected UART pass criteria:",
    "- LIVE_CTRL PASS",
    "- LIVE_AES PASS",
    "- LIVE_SM4 PASS",
    "- SHADOW_AES PASS",
    "- SHADOW_SM4 PASS",
    "- SHADOW_INVALID_SKIP PASS",
    "- UDP gateway shadow mirror PASS",
    "",
    "Sticky Halt contract:",
    "- Shadow DMA poll timeout enters HALTED.",
    "- HALTED is sticky.",
    "- Shadow submit stays best-effort and must fail-open to live.",
    "- SHADOW_TIMEOUT_HALT PASS is a local/contract-only diagnostic, not a normal board-pass requirement.",
    "",
    "Clean boot image structure:",
    "1. [bootloader] fresh fsbl.elf generated from udp_gateway_shadow_mirror_wrapper.xsa",
    "2. fresh udp_gateway_shadow_mirror_wrapper.bit extracted from that same XSA",
    "3. ax7020_udp_gateway_shadow_mirror_app.elf",
    "",
    "Fresh source chain:",
    "- Vivado project: HCS_SOC.xpr",
    "- XSA path: $XsaPath",
    "- XSA extract dir: $xsaExtractDir",
    "- Bitstream path: $stagedBit",
    "- XSCT workspace: $WorkspaceRoot",
    "- Platform name: $PlatformName",
    "- FSBL path: $stagedFsbl",
    "- App API BSP root: $platformSwDir",
    "- App ELF path: $stagedApp",
    "- SHA256: $bootHash",
    "",
    "Current status:",
    "- Shadow First",
    "- PS Mirror",
    "- Sticky Halt",
    "- Combined live direct crypto + hybrid DMA shadow hardware line.",
    "- Board-proven hybrid smoke hash: C85DDC649E523FB03863CB2B9C842E434E173EE546BDB1FCADC56EB467507AD3",
    "- Wrong-port and unaligned contracts remain hardware-enforced",
    "",
    "Board performance capture:",
    "- Output artifacts: board_bench_report.json, board_bench_summary.md",
    "- BENCH capture is control-plane only.",
    "- Required UART evidence for BENCH mode:",
    "  UDP crypto gateway started @ ports 4660(AES) 4661(SM4) 4662(CTRL)",
    "  LIVE_CTRL PASS",
    "- Short payload rows 16B/32B may remain below 1.0x; acceptance is based on average speedup."
) -join "`r`n"

Set-Content -Path $readmePath -Value $readme -Encoding ASCII

Write-Host "Generated shadow mirror BOOT.BIN:"
Write-Host $bootBin
Write-Host "Fresh XSA: $XsaPath"
Write-Host "Fresh FSBL: $stagedFsbl"
Write-Host "Fresh bitstream: $stagedBit"
Write-Host "App ELF: $stagedApp"
Write-Host "SHA256: $bootHash"
Write-Host "bootgen -read: $bootReadPath"
