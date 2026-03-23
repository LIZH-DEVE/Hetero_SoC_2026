[CmdletBinding()]
param(
    [string]$BootgenPath,
    [string]$FsblElf = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\platform\zynq_fsbl\build\fsbl.elf",
    [string]$Bitstream = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\system_wrapper.bit",
    [string]$AppElf = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\network_inject_app\build\network_inject_app.elf",
    [string]$OutputDir = "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\network_inject"
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

    $candidates = @(
        "D:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
        "D:\Xilinx\Vivado\2024.1\bin\bootgen",
        "C:\Xilinx\Vivado\2024.1\bin\bootgen.bat",
        "C:\Xilinx\Vivado\2024.1\bin\bootgen"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "bootgen was not found. Pass -BootgenPath explicitly."
}

function Assert-FileExists {
    param(
        [string]$PathValue,
        [string]$Label
    )

    if (-not (Test-Path $PathValue)) {
        throw "$Label not found: $PathValue"
    }
}

function To-BifPath {
    param([string]$PathValue)
    return ((Resolve-Path $PathValue).Path -replace "\\", "/")
}

$bootgen = Resolve-BootgenExecutable -ConfiguredPath $BootgenPath
Assert-FileExists -PathValue $FsblElf -Label "FSBL ELF"
Assert-FileExists -PathValue $AppElf -Label "Application ELF"

if (-not [string]::IsNullOrWhiteSpace($Bitstream)) {
    Assert-FileExists -PathValue $Bitstream -Label "Bitstream"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$bifPath = Join-Path $OutputDir "boot.bif"
$bootBinPath = Join-Path $OutputDir "BOOT.BIN"

$bifLines = @(
    "the_ROM_image:",
    "{",
    "  [bootloader] $(To-BifPath -PathValue $FsblElf)"
)

if (-not [string]::IsNullOrWhiteSpace($Bitstream)) {
    $bifLines += "  $(To-BifPath -PathValue $Bitstream)"
}

$bifLines += "  $(To-BifPath -PathValue $AppElf)"
$bifLines += "}"

$bifContent = ($bifLines -join "`r`n")

Set-Content -Path $bifPath -Value $bifContent -Encoding ASCII

$args = @(
    "-image", $bifPath,
    "-arch", "zynq",
    "-o", $bootBinPath,
    "-w"
)

& $bootgen @args
if ($LASTEXITCODE -ne 0) {
    throw "bootgen failed."
}

Write-Host "Generated BOOT.BIN:"
Write-Host $bootBinPath
Write-Host "Generated BIF:"
Write-Host $bifPath
