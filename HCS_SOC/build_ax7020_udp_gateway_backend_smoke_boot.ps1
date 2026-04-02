[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$VitisRoot = "D:\Xilinx\Vitis\2024.1",
    [string]$XsctBat = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat",
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
    [string]$XsaPath = "",
    [string]$WorkspaceRoot = "",
    [string]$PlatformName = "ax7020_dma_gateway_hybrid_platform",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$exportXsaScript = Join-Path $workspace "export_dma_gateway_hybrid_xsa.ps1"
$platformScript = Join-Path $workspace "generate_ax7020_standalone_platform.ps1"
$appBuildScript = Join-Path $workspace "build_ax7020_udp_gateway_backend_smoke_app.ps1"
$bootBuildScript = Join-Path $workspace "build_boot_bin.ps1"
$releaseDir = Join-Path $workspace "sd_boot\ax7020_udp_gateway_backend_smoke"
$readmePath = Join-Path $releaseDir "readme.txt"
$appElf = Join-Path $workspace "ax7020_udp_gateway_backend_smoke_app\build\ax7020_udp_gateway_backend_smoke_app.elf"

if ([string]::IsNullOrWhiteSpace($XsaPath)) {
    $XsaPath = Join-Path $workspace "dma_gateway_hybrid_wrapper.xsa"
}
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Join-Path $workspace "ax7020_dma_gateway_hybrid_platform_xsct\workspace"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = $releaseDir
}

function Resolve-BackendApiBspRoot {
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

    throw "Backend smoke platform API BSP root not found under $WorkspaceRoot"
}

function Resolve-BackendFsblElf {
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

    $candidates = @($ConfiguredPath, "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat", "C:\Xilinx\Vivado\2024.1\bin\bootgen.bat")
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "bootgen was not found. Pass -BootgenPath explicitly."
}

foreach ($requiredPath in @($exportXsaScript, $platformScript, $appBuildScript, $bootBuildScript, $XsctBat)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required backend smoke build input not found: $requiredPath"
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
foreach ($staleArtifact in @(
    "BOOT.BIN",
    "fsbl.elf",
    "dma_gateway_hybrid_wrapper.bit",
    "ax7020_udp_gateway_backend_smoke_app.elf",
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

if (-not (Test-Path $XsaPath)) {
    & $exportXsaScript -VivadoBat $VivadoBat -XsaPath $XsaPath
    if ($LASTEXITCODE -ne 0) {
        throw "Hybrid XSA export failed"
    }
} else {
    Write-Host "Reusing existing hybrid XSA:"
    Write-Host $XsaPath
}

try {
    $platformSwDir = Resolve-BackendApiBspRoot -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
    $fsblElf = Resolve-BackendFsblElf -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
    if ($null -eq $fsblElf) {
        throw "fresh fsbl.elf missing"
    }
    Write-Host "Reusing existing hybrid platform workspace:"
    Write-Host $WorkspaceRoot
} catch {
    & $platformScript -XsctBat $XsctBat -XsaPath $XsaPath -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
    if ($LASTEXITCODE -ne 0) {
        throw "Backend smoke platform generation failed"
    }

    $platformSwDir = Resolve-BackendApiBspRoot -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
    $fsblElf = Resolve-BackendFsblElf -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
    if ($null -eq $fsblElf) {
        throw "Fresh backend smoke fsbl.elf not found under $WorkspaceRoot"
    }
}
& $appBuildScript -VitisRoot $VitisRoot -PlatformSwDir $platformSwDir
if ($LASTEXITCODE -ne 0) {
    throw "Backend smoke app build failed"
}

if (-not (Test-Path $appElf)) {
    throw "Backend smoke app ELF not found: $appElf"
}

if (Test-Path $xsaExtractDir) {
    Remove-Item -Recurse -Force $xsaExtractDir
}
New-Item -ItemType Directory -Force -Path $xsaExtractDir | Out-Null

tar -xf $XsaPath -C $xsaExtractDir
if ($LASTEXITCODE -ne 0) {
    throw "Failed to extract backend smoke XSA: $XsaPath"
}

$bitstream = Get-ChildItem -Path $xsaExtractDir -File -Filter *.bit |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $bitstream) {
    throw "No bitstream found inside backend smoke XSA: $XsaPath"
}

$stagedFsbl = Join-Path $OutputDir "fsbl.elf"
$stagedBit = Join-Path $OutputDir "dma_gateway_hybrid_wrapper.bit"
$stagedApp = Join-Path $OutputDir "ax7020_udp_gateway_backend_smoke_app.elf"

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
    throw "Failed to package backend smoke BOOT.BIN"
}

$bootBin = Join-Path $OutputDir "BOOT.BIN"
if (-not (Test-Path $bootBin)) {
    throw "Backend smoke BOOT.BIN not found after packaging: $bootBin"
}

$bootgen = Resolve-BootgenExecutable -ConfiguredPath $BootgenPath
$bootReadPath = Join-Path $OutputDir "bootgen_read.txt"
$bootRead = & $bootgen -read $bootBin 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "bootgen -read failed for backend smoke BOOT.BIN"
}
Set-Content -Path $bootReadPath -Value $bootRead -Encoding ASCII

$bootHash = (Get-FileHash -Algorithm SHA256 -Path $bootBin).Hash

$readme = @(
    "UDP gateway backend smoke image",
    "",
    "Purpose:",
    "- Phase B backend split smoke image for the hybrid ingress line.",
    "- Confirms the direct MMIO backend regression still passes.",
    "- Confirms the DMA probe backend smoke path still passes on the board-proven hybrid wrapper.",
    "- This is not a live cutover image.",
    "- The smoke path is smoke-only and does not bind live UDP ports.",
    "",
    "Expected UART pass criteria:",
    "- DIRECT_BACKEND PASS",
    "- DMA_PROBE EXACT_FIT PASS",
    "- DMA_PROBE SHORT PASS",
    "- DMA_PROBE OVERFLOW PASS",
    "- DMA_PROBE WRONG_PORT PASS",
    "- DMA_PROBE UNALIGNED_REJECT PASS",
    "- DMA_PROBE PASS",
    "- UDP gateway backend smoke PASS",
    "",
    "Clean boot image structure:",
    "1. [bootloader] fresh fsbl.elf generated from dma_gateway_hybrid_wrapper.xsa",
    "2. fresh dma_gateway_hybrid_wrapper.bit extracted from that same XSA",
    "3. ax7020_udp_gateway_backend_smoke_app.elf",
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
    "- Phase B backend split smoke image",
    "- Reuse the board-proven hybrid hardware line",
    "- Board-proven hybrid smoke hash: C85DDC649E523FB03863CB2B9C842E434E173EE546BDB1FCADC56EB467507AD3",
    "- Wrong-port and unaligned contracts remain hardware-enforced"
) -join "`r`n"

Set-Content -Path $readmePath -Value $readme -Encoding ASCII

Write-Host "Generated backend smoke BOOT.BIN:"
Write-Host $bootBin
Write-Host "Fresh XSA: $XsaPath"
Write-Host "Fresh FSBL: $stagedFsbl"
Write-Host "Fresh bitstream: $stagedBit"
Write-Host "App ELF: $stagedApp"
Write-Host "SHA256: $bootHash"
Write-Host "bootgen -read: $bootReadPath"
