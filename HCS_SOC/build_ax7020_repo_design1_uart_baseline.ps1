[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$XsctBat = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat",
    [string]$VitisRoot = "D:\Xilinx\Vitis\2024.1",
    [string]$BootgenPath = "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat"
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
$exportScript = Join-Path $workspace "export_design1_wrapper_xsa.ps1"
$platformScript = Join-Path $workspace "generate_ax7020_standalone_platform.ps1"
$appBuildScript = Join-Path $workspace "build_ax7020_repo_design1_uart_baseline_app.ps1"
$bootBuildScript = Join-Path $workspace "build_boot_bin.ps1"
$xsaPath = Join-Path $workspace "design_1_wrapper.xsa"
$xsctWorkspace = Join-Path $workspace "repo_design1_uart_baseline_xsct\workspace"
$xsaExtractDir = Join-Path $workspace "repo_design1_uart_baseline_xsct\xsa_extract"
$platformName = "ax7020_repo_design1_uart_platform"
$appElf = Join-Path $workspace "ax7020_repo_design1_uart_baseline_app\build\ax7020_repo_design1_uart_baseline_app.elf"
$outputDir = Join-Path $workspace "sd_boot\ax7020_repo_design1_uart_baseline"
$readmePath = Join-Path $outputDir "readme.txt"
$readbackPath = Join-Path $outputDir "bootgen_read.txt"
$bootBinPath = Join-Path $outputDir "BOOT.BIN"

foreach ($path in @($exportScript, $platformScript, $appBuildScript, $bootBuildScript)) {
    if (-not (Test-Path $path)) {
        throw "Required script not found: $path"
    }
}

& powershell -ExecutionPolicy Bypass -File $exportScript -VivadoBat $VivadoBat
if ($LASTEXITCODE -ne 0) {
    throw "design_1 XSA export failed"
}

if (Test-Path $xsaExtractDir) {
    Remove-Item -Recurse -Force $xsaExtractDir
}
New-Item -ItemType Directory -Force -Path $xsaExtractDir | Out-Null
tar -xf $xsaPath -C $xsaExtractDir
if ($LASTEXITCODE -ne 0) {
    throw "Failed to extract XSA: $xsaPath"
}

$bitstream = Join-Path $xsaExtractDir "design_1_wrapper.bit"
if (-not (Test-Path $bitstream)) {
    throw "Fresh design_1 bitstream not found inside exported XSA: $bitstream"
}

& powershell -ExecutionPolicy Bypass -File $platformScript `
    -XsctBat $XsctBat `
    -XsaPath $xsaPath `
    -WorkspaceRoot $xsctWorkspace `
    -PlatformName $platformName
if ($LASTEXITCODE -ne 0) {
    throw "design_1 platform generation failed"
}

$fsblElf = Get-ChildItem -Path $xsctWorkspace -Recurse -File -Filter fsbl.elf |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $fsblElf) {
    throw "design_1 fresh fsbl.elf not found under $xsctWorkspace"
}

$specFile = Get-ChildItem -Path $xsctWorkspace -Recurse -File -Filter Xilinx.spec |
    Where-Object { $_.DirectoryName -match 'standalone_ps7_cortexa9_0' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $specFile) {
    throw "design_1 platform Xilinx.spec not found under $xsctWorkspace"
}
$platformSwDir = $specFile.DirectoryName

& powershell -ExecutionPolicy Bypass -File $appBuildScript `
    -VitisRoot $VitisRoot `
    -PlatformSwDir $platformSwDir
if ($LASTEXITCODE -ne 0) {
    throw "repo design_1 UART baseline app build failed"
}

& powershell -ExecutionPolicy Bypass -File $bootBuildScript `
    -BootgenPath $BootgenPath `
    -FsblElf $fsblElf.FullName `
    -Bitstream $bitstream `
    -AppElf $appElf `
    -OutputDir $outputDir
if ($LASTEXITCODE -ne 0) {
    throw "repo design_1 UART baseline BOOT.BIN generation failed"
}

$bootgen = Resolve-BootgenExecutable -ConfiguredPath $BootgenPath
Invoke-BootgenRead -BootBin $bootBinPath -Bootgen $bootgen -OutputPath $readbackPath
$sha256 = (Get-FileHash -Path $bootBinPath -Algorithm SHA256).Hash

$readme = @"
AX7020 Repo-Owned design_1 UART Baseline

Purpose:
- Repo-owned board startup baseline derived from the current Vivado project.
- Validates the repo's own design_1 handoff chain before any DMA board image is tested.

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from the current design_1_wrapper.xsa
2. fresh design_1_wrapper.bit extracted from that same XSA
3. repo-owned UART baseline application ELF

Fresh source chain:
- Vivado project: HCS_SOC.xpr
- XSA export: design_1_wrapper.xsa via export_design1_wrapper_xsa.ps1 / export_xsa.tcl
- XSCT platform workspace: repo_design1_uart_baseline_xsct\workspace
- FSBL path: $($fsblElf.FullName)
- Bitstream path: $bitstream
- Platform SW dir: $platformSwDir
- App ELF path: $appElf
- SHA256: $sha256

Expected board-side behavior:
- UART prints:
  REPO DESIGN1 UART BASELINE
  UART1 OK
  FRESH_XSA_FSBL_CHAIN
  REPO_HEARTBEAT N
"@

Set-Content -Path $readmePath -Value $readme -Encoding ASCII

Write-Host "Generated repo-owned design_1 UART baseline:"
Write-Host $bootBinPath
Write-Host "SHA256: $sha256"
