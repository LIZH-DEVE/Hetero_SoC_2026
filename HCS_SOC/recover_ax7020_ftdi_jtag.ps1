[CmdletBinding()]
param(
    [ValidateSet("backup", "program", "full_recover")]
    [string]$Action = "backup",
    [string]$VivadoRoot,
    [string]$XsdbPath,
    [string]$BackupPath,
    [string]$ProgramConfigPath,
    [switch]$ConfirmWrite
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ftdi_jtag_common.ps1")

$vivado = Resolve-VivadoRoot -ConfiguredRoot $VivadoRoot
$xsdb = Resolve-XsdbExecutable -ConfiguredPath $XsdbPath

Write-Section "Detected FTDI USB Devices"
$topLevel = @(Get-TopLevelFtdiUsbDevices)
$topLevel | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -Auto

if (-not (Test-SingleTopLevelFtdiDevice)) {
    throw "Exactly one top-level FTDI USB device must be connected before backup/program. Unplug the extra FTDI device(s) and retry."
}

if (-not $BackupPath) {
    $BackupPath = New-TimestampedPath -Prefix "ftdi_eeprom_backup" -Extension "cfg"
}
$readLog = New-TimestampedPath -Prefix "program_ftdi_backup" -Extension "log"

$createdBackup = $false
if ($Action -in @("backup", "full_recover")) {
    Write-Section "EEPROM Backup"
    $backupResult = Invoke-ProgramFtdi -VivadoRoot $vivado -Arguments @("-read", "-fileout=$BackupPath") -LogPath $readLog
    Write-Host $backupResult.Output
    Write-Host ("program_ftdi exit code: {0}" -f $backupResult.ExitCode)
    Write-Host ("program_ftdi log: {0}" -f $backupResult.LogPath)
    if (-not $backupResult.Success -or -not (Test-Path $BackupPath)) {
        throw "EEPROM backup failed; refusing to continue."
    }
    Write-Host ("EEPROM backup file: {0}" -f $BackupPath)
    $createdBackup = $true
}

if ($Action -eq "program" -and -not $BackupPath) {
    throw "Pass -BackupPath when using -Action program."
}

if ($Action -in @("program", "full_recover")) {
    if (-not $ConfirmWrite) {
        throw "EEPROM write is guarded. Re-run with -ConfirmWrite after confirming the backup file is correct."
    }
    if (-not (Test-Path $BackupPath)) {
        throw "Backup file does not exist: $BackupPath"
    }

    if (-not $ProgramConfigPath) {
        $ProgramConfigPath = New-TimestampedPath -Prefix "ftdi_program_config" -Extension "cfg"
    }

    Write-Section "EEPROM Program Config"
    $writeConfig = Get-RequiredWriteConfig -BackupPath $BackupPath
    Write-KeyValueConfig -Config $writeConfig -Path $ProgramConfigPath
    Get-Content $ProgramConfigPath | ForEach-Object { Write-Host $_ }
    Write-Host ("Program config file: {0}" -f $ProgramConfigPath)

    Write-Section "EEPROM Program"
    $writeLog = New-TimestampedPath -Prefix "program_ftdi_write" -Extension "log"
    $writeResult = Invoke-ProgramFtdi -VivadoRoot $vivado -Arguments @("-write", "-filein=$ProgramConfigPath") -LogPath $writeLog
    Write-Host $writeResult.Output
    Write-Host ("program_ftdi exit code: {0}" -f $writeResult.ExitCode)
    Write-Host ("program_ftdi log: {0}" -f $writeResult.LogPath)
    if (-not $writeResult.Success) {
        throw "EEPROM programming failed."
    }

    Write-Section "Post-Write Instructions"
    Write-Host "Power-cycle the board now, then re-run check_ax7020_ftdi_jtag.ps1 and xsdb targets."
}

if ($Action -eq "backup" -or $createdBackup) {
    Write-Section "xsdb Targets"
    $xsdbLog = New-TimestampedPath -Prefix "xsdb_targets_post_backup" -Extension "log"
    $xsdbResult = Invoke-XsdbTargetsCheck -XsdbPath $xsdb -LogPath $xsdbLog
    Write-Host $xsdbResult.Output
    Write-Host ("xsdb targets log: {0}" -f $xsdbResult.LogPath)
}
