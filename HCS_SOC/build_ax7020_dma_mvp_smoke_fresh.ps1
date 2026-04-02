[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$XsctBat = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat",
    [string]$VitisRoot = "D:\Xilinx\Vitis\2024.1",
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
    [ValidateRange(1,8)]
    [int]$CryptoInstances = 2
)

$ErrorActionPreference = "Stop"

function Resolve-BootgenExecutable {
    param([string]$ConfiguredPath)

    if ($ConfiguredPath) {
        if (-not (Test-Path $ConfiguredPath)) {
            throw "bootgen was not found at configured path: $ConfiguredPath"
        }
        return (Resolve-Path $ConfiguredPath).Path
    }

    throw "bootgen path is required"
}

function Invoke-BootgenRead {
    param(
        [string]$BootBin,
        [string]$Bootgen,
        [string]$OutputPath
    )

    $output = & $Bootgen -read $BootBin 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "bootgen -read failed for $BootBin"
    }
    Set-Content -Path $OutputPath -Value $output -Encoding ASCII
}

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$rebuildScript = Join-Path $workspace "rebuild_system_stage1.ps1"
$platformScript = Join-Path $workspace "generate_ax7020_standalone_platform.ps1"
$appBuildScript = Join-Path $workspace "build_ax7020_dma_mvp_smoke_app.ps1"
$bootBuildScript = Join-Path $workspace "build_boot_bin.ps1"
$timingTriageScript = Join-Path $workspace "invoke_vivado_timing_triage.ps1"
$timingParserScript = Join-Path $workspace "read_vivado_timing_summary.ps1"
$xsaPath = Join-Path $workspace "system_wrapper.xsa"
$xsctWorkspace = Join-Path $workspace "repo_system_wrapper_dma_platform_xsct\workspace"
$xsaExtractDir = Join-Path $workspace "repo_system_wrapper_dma_platform_xsct\xsa_extract"
$triageDir = Join-Path $workspace "timing_triage\system_wrapper_current"
$timingSummaryReport = Join-Path $triageDir "timing_summary.rpt"
$routedDcp = Join-Path $workspace "HCS_SOC.runs\impl_1\system_wrapper_routed.dcp"
$platformName = "ax7020_system_wrapper_dma_platform"
$appElf = Join-Path $workspace "ax7020_dma_mvp_smoke_app\build\ax7020_dma_mvp_smoke_app.elf"
$outputDir = Join-Path $workspace "sd_boot\ax7020_dma_mvp_smoke_system"
$readmePath = Join-Path $outputDir "readme.txt"
$readbackPath = Join-Path $outputDir "bootgen_read.txt"
$bootBinPath = Join-Path $outputDir "BOOT.BIN"

foreach ($path in @($rebuildScript, $platformScript, $appBuildScript, $bootBuildScript, $timingTriageScript, $timingParserScript)) {
    if (-not (Test-Path $path)) {
        throw "Required script not found: $path"
    }
}

if (Test-Path $outputDir) {
    Remove-Item -Recurse -Force $outputDir
}

& powershell -ExecutionPolicy Bypass -File $rebuildScript `
    -VivadoBat $VivadoBat `
    -CryptoInstances $CryptoInstances
if ($LASTEXITCODE -ne 0) {
    throw "system_wrapper rebuild failed"
}

& powershell -ExecutionPolicy Bypass -File $timingTriageScript `
    -VivadoBat $VivadoBat `
    -DcpPath $routedDcp `
    -OutputDir $triageDir
if ($LASTEXITCODE -ne 0) {
    throw "system_wrapper timing triage failed"
}

& powershell -ExecutionPolicy Bypass -File $timingParserScript `
    -ReportPath $timingSummaryReport `
    -FailIfViolating
if ($LASTEXITCODE -ne 0) {
    throw "system_wrapper timing gate failed; DMA smoke image is not board-eligible"
}

if (Test-Path $xsaExtractDir) {
    Remove-Item -Recurse -Force $xsaExtractDir
}
New-Item -ItemType Directory -Force -Path $xsaExtractDir | Out-Null
tar -xf $xsaPath -C $xsaExtractDir
if ($LASTEXITCODE -ne 0) {
    throw "Failed to extract XSA: $xsaPath"
}

$bitstream = Join-Path $xsaExtractDir "system_wrapper.bit"
if (-not (Test-Path $bitstream)) {
    throw "Fresh system_wrapper bitstream not found inside exported XSA: $bitstream"
}

& powershell -ExecutionPolicy Bypass -File $platformScript `
    -XsctBat $XsctBat `
    -XsaPath $xsaPath `
    -WorkspaceRoot $xsctWorkspace `
    -PlatformName $platformName
if ($LASTEXITCODE -ne 0) {
    throw "system_wrapper platform generation failed"
}

$fsblElf = Get-ChildItem -Path $xsctWorkspace -Recurse -File -Filter fsbl.elf |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $fsblElf) {
    throw "system_wrapper fresh fsbl.elf not found under $xsctWorkspace"
}
$platformSwDir = Join-Path $fsblElf.DirectoryName "zynq_fsbl_bsp\ps7_cortexa9_0"
if (-not (Test-Path $platformSwDir)) {
    throw "system_wrapper fresh FSBL BSP processor root not found: $platformSwDir"
}

& powershell -ExecutionPolicy Bypass -File $appBuildScript `
    -VitisRoot $VitisRoot `
    -PlatformSwDir $platformSwDir
if ($LASTEXITCODE -ne 0) {
    throw "DMA smoke app build failed"
}

& powershell -ExecutionPolicy Bypass -File $bootBuildScript `
    -BootgenPath $BootgenPath `
    -FsblElf $fsblElf.FullName `
    -Bitstream $bitstream `
    -AppElf $appElf `
    -OutputDir $outputDir
if ($LASTEXITCODE -ne 0) {
    throw "DMA smoke BOOT.BIN generation failed"
}

$bootgen = Resolve-BootgenExecutable -ConfiguredPath $BootgenPath
Invoke-BootgenRead -BootBin $bootBinPath -Bootgen $bootgen -OutputPath $readbackPath
$sha256 = (Get-FileHash -Path $bootBinPath -Algorithm SHA256).Hash

$readme = @"
AX7020 DMA MVP Smoke Image

Purpose:
- Repo-owned system_wrapper DMA smoke derived from the current Vivado project.
- Board-side DMA bring-up image after the vendor ps_uart and repo design_1 UART baselines pass.

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from the current system_wrapper.xsa
2. fresh system_wrapper.bit extracted from that same XSA
3. ax7020_dma_mvp_smoke_app.elf

Fresh source chain:
- Vivado project: HCS_SOC.xpr
- system rebuild: rebuild_system_stage1.ps1 / rebuild_system_stage1.tcl
- XSA export: system_wrapper.xsa
- XSCT platform workspace: repo_system_wrapper_dma_platform_xsct\workspace
- Timing gate report: $timingSummaryReport
- FSBL path: $($fsblElf.FullName)
- Bitstream path: $bitstream
- Platform SW dir: $platformSwDir
- App ELF path: $appElf
- SHA256: $sha256

Board-side scope:
1. UART banner and DMA CSR snapshot
2. One normal descriptor via PS CSR injector -> PBM -> Crypto -> DMA -> CSW
3. One error descriptor returning CSW ERR + STS

Board-admission rule:
- This BOOT.BIN is generated only when system_wrapper timing is clean:
  WNS >= 0, TNS = 0, setup failing endpoints = 0, hold failing endpoints = 0
"@

Set-Content -Path $readmePath -Value $readme -Encoding ASCII

Write-Host "Generated fresh system_wrapper DMA smoke image:"
Write-Host $bootBinPath
Write-Host "SHA256: $sha256"
