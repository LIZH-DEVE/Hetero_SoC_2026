[CmdletBinding()]
param(
    [string]$XsdbPath,
    [string]$SessionDir
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ftdi_jtag_common.ps1")

$xsdb = Resolve-XsdbExecutable -ConfiguredPath $XsdbPath
Stop-XilinxJtagProcesses | Out-Null
$oldNativePreference = $null
if (Test-Path Variable:\PSNativeCommandUseErrorActionPreference) {
    $oldNativePreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
}

if ([string]::IsNullOrWhiteSpace($SessionDir)) {
    $SessionDir = New-RecoverySessionDirectory
} else {
    New-Item -ItemType Directory -Force -Path $SessionDir | Out-Null
}

$snapshot = Export-Ax7020FtdiSnapshot -OutputDirectory $SessionDir -XsdbPath $xsdb -Prefix "post"
$d2xxLog = Join-Path $SessionDir "post_ftd2xx_dump.log"
$d2xxSessionDir = Join-Path $SessionDir "post_ftd2xx"

Write-Section "Post-Recovery Snapshot"
Write-Host ("Session directory: {0}" -f $SessionDir)
Write-Host ("Post-check present devices: {0}" -f $snapshot.PresentDevicesPath)
Write-Host ("Post-check board device: {0}" -f $snapshot.BoardDevicePath)
Write-Host ("Post-check board driver: {0}" -f $snapshot.BoardDriverPath)
Write-Host ("Post-check xsdb targets: {0}" -f $snapshot.TargetsPath)
Write-Host ("Post-check D2XX dump: {0}" -f $d2xxLog)

$board = Get-Ax7020BoardFtdiDevice | Select-Object -First 1
if ($board) {
    Write-Host ("Board FT232HL is present: {0}" -f $board.InstanceId)
} else {
    Write-Warning "Board FT232HL (VID_0403&PID_6014) is not present after FT_Prog write."
}

$pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
$python = Get-Command python -ErrorAction SilentlyContinue
try {
if ($pythonLauncher) {
    $repairScript = Join-Path $PSScriptRoot "repair_ax7020_ftdi_user_area.py"
    New-Item -ItemType Directory -Force -Path $d2xxSessionDir | Out-Null
    $d2xxOutput = & $pythonLauncher.Source -3 $repairScript --session-dir $d2xxSessionDir 2>&1 | Out-String
    Set-Content -Path $d2xxLog -Value $d2xxOutput -Encoding UTF8

    Write-Section "D2XX Device Snapshot"
    Write-Host $d2xxOutput.TrimEnd()
} elseif ($python -and ($python.Source -notmatch 'WindowsApps\\python.exe$')) {
    $repairScript = Join-Path $PSScriptRoot "repair_ax7020_ftdi_user_area.py"
    New-Item -ItemType Directory -Force -Path $d2xxSessionDir | Out-Null
    $d2xxOutput = & $python.Source $repairScript --session-dir $d2xxSessionDir 2>&1 | Out-String
    Set-Content -Path $d2xxLog -Value $d2xxOutput -Encoding UTF8

    Write-Section "D2XX Device Snapshot"
    Write-Host $d2xxOutput.TrimEnd()
} else {
    "Neither py -3 nor a real python.exe was found; D2XX snapshot was skipped." | Set-Content -Path $d2xxLog -Encoding UTF8
    Write-Warning "Neither py -3 nor a real python.exe was found; D2XX snapshot was skipped."
}
} finally {
    if ($null -ne $oldNativePreference) {
        $PSNativeCommandUseErrorActionPreference = $oldNativePreference
    }
}

$targetsOutput = Get-Content -Raw $snapshot.TargetsPath
Write-Section "xsdb Targets Output"
Write-Host $targetsOutput.TrimEnd()

if ($targetsOutput -match 'DAP|APU|Cortex-A9') {
    Write-Host "PASS: xsdb can now see Zynq targets."
} else {
    Write-Warning "FAIL: xsdb targets is still empty."
    Write-Host "STOP: Payload A failed. Do not continue onboard EEPROM guessing."
    Write-Host "Next step: use an external DLC10 / Platform Cable USB II compatible downloader."
}
