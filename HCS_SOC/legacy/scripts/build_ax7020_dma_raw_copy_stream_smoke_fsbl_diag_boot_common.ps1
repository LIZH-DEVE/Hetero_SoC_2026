[CmdletBinding()]
param(
    [ValidateSet("trace", "nopostcfg", "handofflite", "handoffdelay")]
    [string]$Variant,
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$VitisRoot = "D:\Xilinx\Vitis\2024.1",
    [string]$XsctBat = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat",
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
    [string]$XsaPath = "",
    [string]$WorkspaceRoot = "",
    [string]$PlatformName = "ax7020_dma_stream_smoke_platform",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$platformScript = Join-Path $workspace "generate_ax7020_standalone_platform.ps1"
$patchScript = Join-Path $workspace "patch_ax7020_stream_smoke_fsbl_for_diag.ps1"
$appBuildScript = Join-Path $workspace "build_ax7020_dma_raw_copy_stream_smoke_app.ps1"
$appElf = Join-Path $workspace "ax7020_dma_raw_copy_stream_smoke_app\build\ax7020_dma_raw_copy_stream_smoke_app.elf"

if ([string]::IsNullOrWhiteSpace($XsaPath)) {
    $XsaPath = Join-Path $workspace "stream_smoke_dma_wrapper.xsa"
}
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Join-Path $workspace "ax7020_dma_stream_smoke_platform_xsct\workspace"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $releaseName = switch ($Variant) {
        "trace" { "ax7020_dma_raw_copy_stream_smoke_fsbl_trace" }
        "nopostcfg" { "ax7020_dma_raw_copy_stream_smoke_fsbl_nopostcfg" }
        "handofflite" { "ax7020_dma_raw_copy_stream_smoke_fsbl_handofflite" }
        "handoffdelay" { "ax7020_dma_raw_copy_stream_smoke_fsbl_handoffdelay" }
    }
    $OutputDir = Join-Path $workspace "sd_boot\$releaseName"
}

function Resolve-StreamSmokeApiBspRoot {
    param([string]$WorkspaceRoot)

    $candidates = @(
        (Join-Path $WorkspaceRoot "ax7020_dma_stream_smoke_platform\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0"),
        (Join-Path $WorkspaceRoot "standalone_bsp\ps7_cortexa9_0")
    )

    foreach ($candidate in $candidates) {
        if ((Test-Path $candidate) -and (Test-Path (Join-Path $candidate "include\xparameters.h"))) {
            return $candidate
        }
    }

    throw "Fresh stream-smoke API BSP root not found under $WorkspaceRoot"
}

function Resolve-StreamSmokeFsblElf {
    param([string]$WorkspaceRoot, [string]$PlatformName)

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

    $candidates = @($ConfiguredPath, "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat", "C:\Xilinx\Vivado\2024.1\bin\bootgen.bat")
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "bootgen was not found. Pass -BootgenPath explicitly."
}

foreach ($requiredPath in @($platformScript, $patchScript, $appBuildScript, $XsctBat, $XsaPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required stream-smoke FSBL diagnostic build input not found: $requiredPath"
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
foreach ($staleArtifact in @(
    "BOOT.BIN",
    "boot.bif",
    "fsbl.elf",
    "stream_smoke_dma_wrapper.bit",
    "ax7020_dma_raw_copy_stream_smoke_app.elf",
    "bootgen_read.txt",
    "readme.txt"
)) {
    $stalePath = Join-Path $OutputDir $staleArtifact
    if (Test-Path $stalePath) {
        Remove-Item -Force -LiteralPath $stalePath
    }
}

$xsaExtractDir = Join-Path $workspace ("stream_smoke_{0}_xsa_extract" -f $Variant)
if (Test-Path $xsaExtractDir) {
    Remove-Item -Recurse -Force $xsaExtractDir
}
New-Item -ItemType Directory -Force -Path $xsaExtractDir | Out-Null

& $platformScript -XsctBat $XsctBat -XsaPath $XsaPath -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
if ($LASTEXITCODE -ne 0) {
    throw "Dedicated stream-smoke platform generation failed for $Variant diagnostic image"
}

& $patchScript -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName -Variant $Variant -VitisRoot $VitisRoot
if ($LASTEXITCODE -ne 0) {
    throw "Dedicated stream-smoke FSBL patch/rebuild failed for $Variant diagnostic image"
}

tar -xf $XsaPath -C $xsaExtractDir
if ($LASTEXITCODE -ne 0) {
    throw "Failed to extract stream-smoke XSA: $XsaPath"
}

$bitstream = Get-ChildItem -Path $xsaExtractDir -File -Filter *.bit |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $bitstream) {
    throw "No bitstream found inside stream-smoke XSA: $XsaPath"
}

$fsblElf = Resolve-StreamSmokeFsblElf -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
if ($null -eq $fsblElf) {
    throw "Patched stream-smoke fsbl.elf not found under $WorkspaceRoot"
}
$platformSwDir = Resolve-StreamSmokeApiBspRoot -WorkspaceRoot $WorkspaceRoot

& $appBuildScript -VitisRoot $VitisRoot -PlatformSwDir $platformSwDir
if ($LASTEXITCODE -ne 0) {
    throw "Stream-smoke app build failed for $Variant diagnostic image"
}

foreach ($requiredPath in @($appElf, $fsblElf.FullName, $bitstream.FullName)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required $Variant diagnostic artifact not found: $requiredPath"
    }
}

$bootgen = Resolve-BootgenExecutable -ConfiguredPath $BootgenPath
$stagedFsbl = Join-Path $OutputDir "fsbl.elf"
$stagedBit = Join-Path $OutputDir "stream_smoke_dma_wrapper.bit"
$stagedApp = Join-Path $OutputDir "ax7020_dma_raw_copy_stream_smoke_app.elf"
$bootBif = Join-Path $OutputDir "boot.bif"
$bootBin = Join-Path $OutputDir "BOOT.BIN"
$bootRead = Join-Path $OutputDir "bootgen_read.txt"
$readmePath = Join-Path $OutputDir "readme.txt"

Copy-Item -Path $fsblElf.FullName -Destination $stagedFsbl -Force
Copy-Item -Path $bitstream.FullName -Destination $stagedBit -Force
Copy-Item -Path $appElf -Destination $stagedApp -Force

@(
    "the_ROM_image:",
    "{",
    "  [bootloader] fsbl.elf",
    "  stream_smoke_dma_wrapper.bit",
    "  ax7020_dma_raw_copy_stream_smoke_app.elf",
    "}"
) | Set-Content -Path $bootBif -Encoding ASCII

Push-Location $OutputDir
try {
    & $bootgen -image $bootBif -arch zynq -o $bootBin -w
    if ($LASTEXITCODE -ne 0) {
        throw "boot image generation failed for $Variant diagnostic image"
    }
}
finally {
    Pop-Location
}

$readback = & $bootgen -read $bootBin 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "bootgen -read failed for $Variant diagnostic image"
}
Set-Content -Path $bootRead -Value $readback -Encoding ASCII

$bootHash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash
$variantSummary = switch ($Variant) {
    "trace" {
@"
Purpose:
- Dedicated stream-smoke FSBL trace image for with-bit root-cause isolation.
- Uses the dedicated stream-smoke FSBL, dedicated stream-smoke bitstream, and dedicated stream-smoke app.
- Adds post-ps7_init UART breadcrumbs only. First trusted breadcrumb is AFTER_PS7_INIT.
- No ENTER_MAIN breadcrumb is emitted.

Expected board-side diagnostic markers:
- FSBL_DIAG AFTER_PS7_INIT
- FSBL_DIAG BEFORE_PCAP_LOAD
- FSBL_DIAG AFTER_PCAP_LOAD
- FSBL_DIAG BEFORE_POST_CONFIG
- FSBL_DIAG AFTER_POST_CONFIG
- FSBL_DIAG BEFORE_HANDOFF
"@
    }
    "nopostcfg" {
@"
Purpose:
- Dedicated stream-smoke FSBL no-post-config image for with-bit root-cause isolation.
- Uses the dedicated stream-smoke FSBL, dedicated stream-smoke bitstream, and dedicated stream-smoke app.
- Skips ps7_post_config() only on the with-bit path while preserving the rest of handoff flow.
- First trusted breadcrumb is AFTER_PS7_INIT. No ENTER_MAIN breadcrumb is emitted.

Expected board-side diagnostic markers:
- FSBL_DIAG AFTER_PS7_INIT
- FSBL_DIAG BEFORE_PCAP_LOAD
- FSBL_DIAG AFTER_PCAP_LOAD
- FSBL_DIAG BEFORE_POST_CONFIG
- FSBL_DIAG AFTER_POST_CONFIG
- FSBL_DIAG BEFORE_HANDOFF

If the stream-smoke app reaches:
- DMA stream smoke PASS
then the remaining blocker is concentrated in the dedicated FSBL post-config / with-bit handoff window.
"@
    }
    "handofflite" {
@"
Purpose:
- Dedicated stream-smoke FSBL handofflite image for minimal-perturbation root-cause isolation.
- Uses the dedicated stream-smoke FSBL, dedicated stream-smoke bitstream, and dedicated stream-smoke app.
- Keeps only the handoff-window UART breadcrumbs inside FsblHandoff().
- Intentionally omits AFTER_PS7_INIT / BEFORE_PCAP_LOAD / AFTER_PCAP_LOAD.

Expected board-side diagnostic markers:
- FSBL_DIAG BEFORE_POST_CONFIG
- FSBL_DIAG AFTER_POST_CONFIG
- FSBL_DIAG BEFORE_HANDOFF
"@
    }
    "handoffdelay" {
@"
Purpose:
- Dedicated stream-smoke FSBL handoffdelay image for minimal-perturbation root-cause isolation.
- Uses the dedicated stream-smoke FSBL, dedicated stream-smoke bitstream, and dedicated stream-smoke app.
- Adds two fixed delay-spin perturbations in the with-bit handoff path and emits no new UART breadcrumbs.
- Delay points are after ps7_post_config() and before FsblHookBeforeHandoff().

Expected board-side diagnostic markers:
- No new FSBL_DIAG breadcrumbs are expected from the FSBL.
- Board pass is judged only by the stream-smoke app UART log.
"@
    }
}

$readme = @"
AX7020 Stream-Smoke FSBL Diagnostic ($Variant)

$variantSummary

Clean boot image structure:
1. [bootloader] patched dedicated stream-smoke fsbl.elf
2. stream_smoke_dma_wrapper.bit
3. ax7020_dma_raw_copy_stream_smoke_app.elf

Source chain:
- XSA path: $XsaPath
- XSCT workspace: $WorkspaceRoot
- Platform name: $PlatformName
- Patched FSBL path: $($fsblElf.FullName)
- App API BSP root: $platformSwDir
- App ELF path: $appElf
- SHA256: $bootHash

Current policy:
- official dedicated stream-smoke image remains experimental
- temporary board-proven Phase 3 baseline remains ax7020_design1fsbl_stream_smoke_app
"@

Set-Content -Path $readmePath -Value $readme -Encoding ASCII

Write-Host "Generated stream-smoke FSBL diagnostic BOOT.BIN:"
Write-Host $bootBin
Write-Host "Variant: $Variant"
Write-Host "Patched FSBL: $($fsblElf.FullName)"
Write-Host "Bitstream: $($bitstream.FullName)"
Write-Host "App ELF: $appElf"
Write-Host "bootgen -read: $bootRead"
Write-Host "SHA256: $bootHash"
