[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\\Xilinx\\Vitis\\2024.1",
    [string]$OfficialRoot = "D:\\FPGAhanjia\\Hetero_SoC_2026_3\\AX7020_2023.1\\course_s2_vitis\\06_net_test\\Vitis\\design_1_wrapper",
    [string]$BootgenPath,
    [string]$OutputRoot = "D:\\FPGAhanjia\\Hetero_SoC_2026_3\\Hetero_SoC_2026\\HCS_SOC\\sd_boot\\official_platform_smoke"
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$makeExe = Join-Path $VitisRoot "gnuwin\\bin\\make.exe"
$gccBin = Join-Path $VitisRoot "gnu\\aarch32\\nt\\gcc-arm-none-eabi\\bin"
$bootgenScript = Join-Path $workspace "build_boot_bin.ps1"
$appBuildScript = Join-Path $workspace "build_ax7020_official_uart_smoke_app.ps1"
$officialFsblDir = Join-Path $OfficialRoot "zynq_fsbl"
$officialFsblElf = Join-Path $officialFsblDir "fsbl.elf"
$officialBitstream = Join-Path $OfficialRoot "hw\\design_1_wrapper.bit"
$smokeAppElf = Join-Path $workspace "ax7020_official_uart_smoke_app\\build\\ax7020_official_uart_smoke_app.elf"
$imageADir = Join-Path $OutputRoot "image_a_nobit"
$imageBDir = Join-Path $OutputRoot "image_b_withbit"
$readbackA = Join-Path $imageADir "bootgen_read.txt"
$readbackB = Join-Path $imageBDir "bootgen_read.txt"

foreach ($pathInfo in @(
    @{ Label = "GNU make"; Path = $makeExe },
    @{ Label = "GCC bin directory"; Path = $gccBin },
    @{ Label = "Official FSBL directory"; Path = $officialFsblDir },
    @{ Label = "Official bitstream"; Path = $officialBitstream },
    @{ Label = "BOOT build script"; Path = $bootgenScript },
    @{ Label = "Smoke app build script"; Path = $appBuildScript }
)) {
    if (-not (Test-Path $pathInfo.Path)) {
        throw "$($pathInfo.Label) not found: $($pathInfo.Path)"
    }
}

function Remove-OfficialFsblArtifacts {
    param([string]$FsblDir)

    $patterns = @("*.o", "*.d", "fsbl.elf")
    foreach ($pattern in $patterns) {
        Get-ChildItem -Path $FsblDir -Filter $pattern -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    $libxil = Join-Path $FsblDir "zynq_fsbl_bsp\\ps7_cortexa9_0\\lib\\libxil.a"
    if (Test-Path $libxil) {
        Remove-Item -Force $libxil -ErrorAction SilentlyContinue
    }
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

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$env:PATH = "$gccBin;$env:PATH"
$env:RDI_PLATFORM = "win64"

Remove-OfficialFsblArtifacts -FsblDir $officialFsblDir
Push-Location $officialFsblDir
try {
    & $makeExe
    if ($LASTEXITCODE -ne 0) {
        throw "Official FSBL build failed."
    }
} finally {
    Pop-Location
}

if (-not (Test-Path $officialFsblElf)) {
    throw "Official FSBL ELF not found after build: $officialFsblElf"
}

& $appBuildScript -VitisRoot $VitisRoot -OfficialRoot $OfficialRoot
if ($LASTEXITCODE -ne 0) {
    throw "Official UART smoke app build failed."
}

if (-not (Test-Path $smokeAppElf)) {
    throw "Official UART smoke app ELF not found: $smokeAppElf"
}

& $bootgenScript -BootgenPath $BootgenPath -FsblElf $officialFsblElf -Bitstream " " -AppElf $smokeAppElf -OutputDir $imageADir
if ($LASTEXITCODE -ne 0) {
    throw "Image A build failed."
}

& $bootgenScript -BootgenPath $BootgenPath -FsblElf $officialFsblElf -Bitstream $officialBitstream -AppElf $smokeAppElf -OutputDir $imageBDir
if ($LASTEXITCODE -ne 0) {
    throw "Image B build failed."
}

$resolvedBootgen = if ($BootgenPath) { $BootgenPath } else { "D:\\Xilinx\\Vivado\\2024.1\\bin\\bootgen.bat" }
Invoke-BootgenRead -BootBin (Join-Path $imageADir "BOOT.BIN") -Bootgen $resolvedBootgen -OutputPath $readbackA
Invoke-BootgenRead -BootBin (Join-Path $imageBDir "BOOT.BIN") -Bootgen $resolvedBootgen -OutputPath $readbackB

Write-Host "Official platform smoke artifacts:"
Write-Host "  FSBL: $officialFsblElf"
Write-Host "  APP : $smokeAppElf"
Write-Host "  Image A: $(Join-Path $imageADir 'BOOT.BIN')"
Write-Host "  Image B: $(Join-Path $imageBDir 'BOOT.BIN')"
Write-Host "  Readback A: $readbackA"
Write-Host "  Readback B: $readbackB"
