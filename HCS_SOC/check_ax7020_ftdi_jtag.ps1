[CmdletBinding()]
param(
    [string]$VivadoRoot,
    [string]$XsdbPath,
    [string]$ReadbackPath,
    [switch]$SkipProgramFtdi,
    [switch]$SkipXsdb
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ftdi_jtag_common.ps1")

$vivado = Resolve-VivadoRoot -ConfiguredRoot $VivadoRoot
$xsdb = Resolve-XsdbExecutable -ConfiguredPath $XsdbPath

Write-Section "Detected FTDI USB Devices"
$ftdiUsb = @(Get-FtdiUsbDevices)
if ($ftdiUsb.Count -eq 0) {
    Write-Warning "No FTDI USB devices detected."
} else {
    $ftdiUsb | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -Auto
}

$topLevel = @(Get-TopLevelFtdiUsbDevices)
Write-Host ("Top-level FTDI USB device count: {0}" -f $topLevel.Count)
$boardDevice = Get-Ax7020BoardFtdiDevice | Select-Object -First 1
if ($boardDevice) {
    Write-Host ("AX7020 board FT232HL candidate: {0}" -f $boardDevice.InstanceId)
} else {
    Write-Warning "AX7020 board FT232HL (VID_0403&PID_6014) was not detected."
}

if (-not $ReadbackPath) {
    $ReadbackPath = New-TimestampedPath -Prefix "ftdi_readback" -Extension "cfg"
}
$readLog = New-TimestampedPath -Prefix "program_ftdi_read" -Extension "log"
$xsdbLog = New-TimestampedPath -Prefix "xsdb_targets" -Extension "log"

Write-Section "program_ftdi Runtime Files"
$runtimeStatus = Get-ProgramFtdiRuntimeStatus -VivadoRoot $vivado
$runtimeStatus | Format-Table -Auto Name, Exists, Path
if (-not (($runtimeStatus | Where-Object { $_.Name -eq 'tcl85t.dll' }).Exists)) {
    Write-Warning "program_ftdi's FTDI Tcl bridge depends on tcl85t.dll, but Vivado 2024.1 does not currently provide it in the expected runtime path."
}

if (-not $SkipProgramFtdi) {
    Write-Section "program_ftdi Readback"
    if (-not (Test-SingleTopLevelFtdiDevice)) {
        Write-Warning "program_ftdi requires exactly one top-level FTDI USB device. Unplug the extra FTDI device(s) and retry."
    } else {
        $readResult = Invoke-ProgramFtdi -VivadoRoot $vivado -Arguments @("-read", "-fileout=$ReadbackPath") -LogPath $readLog
        Write-Host $readResult.Output
        Write-Host ("program_ftdi exit code: {0}" -f $readResult.ExitCode)
        Write-Host ("program_ftdi log: {0}" -f $readResult.LogPath)
        Write-Host ("program_ftdi runtime dir: {0}" -f $readResult.RuntimeDir)
        if ($readResult.Success -and (Test-Path $ReadbackPath)) {
            Write-Host ("EEPROM readback file: {0}" -f $ReadbackPath)
        } else {
            Write-Warning "program_ftdi readback did not complete successfully."
        }
    }
}

if (-not $SkipXsdb) {
    Write-Section "xsdb Targets"
    $xsdbResult = Invoke-XsdbTargetsCheck -XsdbPath $xsdb -LogPath $xsdbLog
    Write-Host $xsdbResult.Output
    Write-Host ("xsdb targets log: {0}" -f $xsdbResult.LogPath)
}
