[CmdletBinding()]
param(
    [string]$XsctPath = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat",
    [string]$BitstreamPath = "",
    [string]$Ps7InitPath = "",
    [string]$ElfPath = "",
    [uint32]$DdrProbeAddress = 0x00100000,
    [switch]$ValidateOnly,
    [switch]$SkipBitstream,
    [switch]$SkipRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$tclScript = Join-Path $workspace "download_ax7020_udp_gateway_shadow_mirror_jtag.tcl"

if ([string]::IsNullOrWhiteSpace($BitstreamPath)) {
    $BitstreamPath = Join-Path $workspace "sd_boot\ax7020_udp_gateway_shadow_mirror\udp_gateway_shadow_mirror_wrapper.bit"
}
if ([string]::IsNullOrWhiteSpace($Ps7InitPath)) {
    $Ps7InitPath = Join-Path $workspace "ax7020_udp_gateway_shadow_mirror_platform_xsct\workspace\ax7020_udp_gateway_shadow_mirror_platform\hw\ps7_init.tcl"
}
if ([string]::IsNullOrWhiteSpace($ElfPath)) {
    $ElfPath = Join-Path $workspace "ax7020_udp_gateway_shadow_mirror_app\build\ax7020_udp_gateway_shadow_mirror_app.elf"
}

foreach ($requiredPath in @($XsctPath, $tclScript, $Ps7InitPath, $ElfPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required path not found: $requiredPath"
    }
}

if (-not $SkipBitstream -and -not (Test-Path $BitstreamPath)) {
    throw "Bitstream not found: $BitstreamPath"
}

$xsctArgs = @(
    $tclScript,
    "-bitstream", $BitstreamPath,
    "-ps7-init", $Ps7InitPath,
    "-elf", $ElfPath,
    "-ddr-probe-addr", ('0x{0:X8}' -f $DdrProbeAddress)
)
if ($ValidateOnly) {
    $xsctArgs += "-validate-only"
}
if ($SkipBitstream) {
    $xsctArgs += "-skip-bitstream"
}
if ($SkipRun) {
    $xsctArgs += "-skip-run"
}

function Invoke-XsctCommand {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $XsctPath `
            -ArgumentList $Arguments `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $stdout = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw } else { "" }
        $stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { "" }
        $combined = ($stdout + $stderr).TrimEnd()

        return [PSCustomObject]@{
            ExitCode = $proc.ExitCode
            Output = $combined
        }
    }
    finally {
        Remove-Item $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
    }
}

$result = Invoke-XsctCommand -Arguments $xsctArgs
$output = $result.Output
$exitCode = $result.ExitCode
if ($output) {
    Write-Host $output
}

if ($exitCode -ne 0) {
    throw "xsct exited with code $exitCode"
}

$successToken = if ($ValidateOnly) { "JTAG_VALIDATE_OK" } else { "JTAG_RUN_DONE" }
if ($output -notmatch [regex]::Escape($successToken)) {
    throw "xsct completed without success token: $successToken"
}
