[CmdletBinding()]
param(
    [string]$XsdbPath,
    [string]$SessionDir,
    [string]$FtProgPath,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ftdi_jtag_common.ps1")

$xsdb = Resolve-XsdbExecutable -ConfiguredPath $XsdbPath
Stop-XilinxJtagProcesses | Out-Null

if ([string]::IsNullOrWhiteSpace($SessionDir)) {
    $SessionDir = New-RecoverySessionDirectory
} else {
    New-Item -ItemType Directory -Force -Path $SessionDir | Out-Null
}

$backupPath = Join-Path $SessionDir "ax7020_ft_prog_backup.xml"
$payloadAPath = Join-Path $SessionDir "ax7020_ft_prog_payloadA.xml"
$userAreaSessionDir = Join-Path $SessionDir "payloadA_user_area"
$instructionsPath = Join-Path $SessionDir "FT_PROG_STEPS.txt"
$repairScript = Resolve-FtdiUserAreaRepairScript

Write-Section "FTDI Presence Check"
$devices = @(Get-FtdiUsbDevices)
$devices | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -Auto

$board = Get-Ax7020BoardFtdiDevice | Select-Object -First 1
if (-not $board) {
    throw "AX7020 board FT232HL (VID_0403&PID_6014) is not currently present."
}

$snapshot = Export-Ax7020FtdiSnapshot -OutputDirectory $SessionDir -XsdbPath $xsdb -Prefix "pre"

Write-Section "Recovery Session"
Write-Host ("Session directory: {0}" -f $SessionDir)
Write-Host ("FT_Prog backup target: {0}" -f $backupPath)
Write-Host ("FT_Prog Payload A target: {0}" -f $payloadAPath)
Write-Host ("Pre-check present devices: {0}" -f $snapshot.PresentDevicesPath)
Write-Host ("Pre-check board device: {0}" -f $snapshot.BoardDevicePath)
Write-Host ("Pre-check board driver: {0}" -f $snapshot.BoardDriverPath)
Write-Host ("Pre-check xsdb targets: {0}" -f $snapshot.TargetsPath)

$instructions = @(
    "AX7020 FT_Prog Recovery Session"
    ""
    ("SessionDir={0}" -f $SessionDir)
    ("BackupTemplate={0}" -f $backupPath)
    ("PayloadATemplate={0}" -f $payloadAPath)
    ""
    "1. Keep only the onboard JTAG cable connected. Leave J13 in JTAG mode."
    "2. In FT_Prog, click Scan and Parse."
    "3. Confirm the target device remains VID_0403&PID_6014."
    ("4. Save the current device template to: {0}" -f $backupPath)
    ("5. Save the Payload A template to: {0}" -f $payloadAPath)
    "6. Modify only the following fields for Payload A:"
    "   - Hardware Specific -> Port A -> Hardware = 245 FIFO"
    "   - Hardware Specific -> Port A -> Driver = D2XX Direct"
    "   - Hardware Specific -> Port A -> Virtual Com Port (VCP) = Disabled"
    "   - USB String Descriptors -> Manufacturer = Xilinx"
    "   - USB String Descriptors -> Product Description = Xilinx USB Cable"
    "   - USB String Descriptors -> Serial Number = 210512180081A"
    "7. Keep VID/PID = 0403 / 6014. Do NOT change power mode, Max Power, CBUS, or other descriptor fields."
    "8. Program the EEPROM in FT_Prog."
    "10. Uninstall the current USB Serial Converter device instance in Device Manager without deleting the driver package."
    "11. Unplug the onboard JTAG cable, power-cycle the board for 5 to 10 seconds, then reconnect JTAG."
    ("12. After power-cycle, run: powershell -ExecutionPolicy Bypass -File ""{0}"" -SessionDir ""{1}""" -f (Join-Path $PSScriptRoot "verify_ax7020_ft_prog_recovery.ps1"), $SessionDir)
    "13. If xsdb targets is still empty after this Payload A validation, stop EEPROM experimentation and switch to an external DLC10 / Platform Cable compatible downloader."
)
if ($repairScript) {
    $instructions = @(
        $instructions[0..8]
        ("9. Write the fixed Xilinx User Area payload with: py -3 ""{0}"" --session-dir ""{1}"" --write --confirm-write" -f $repairScript, $userAreaSessionDir)
        $instructions[9..($instructions.Count - 1)]
    )
} else {
    $instructions = @(
        $instructions[0..8]
        "9. User area repair script was not found locally; skip user-area write preparation until the helper script is restored."
        $instructions[9..($instructions.Count - 1)]
    )
}
Set-Content -Path $instructionsPath -Value $instructions -Encoding UTF8
Write-Host ("Instructions file: {0}" -f $instructionsPath)

$resolvedFtProg = $FtProgPath
if ([string]::IsNullOrWhiteSpace($resolvedFtProg)) {
    $resolvedFtProg = Find-FtProgExecutable
}
$installerPath = Find-FtProgInstaller

Write-Section "FT_Prog Launch"
if ($resolvedFtProg) {
    Write-Host ("FT_Prog found: {0}" -f $resolvedFtProg)
    if (-not $NoLaunch) {
        Start-Process -FilePath $resolvedFtProg
    }
} elseif ($installerPath) {
    Write-Host ("FT_Prog installer found: {0}" -f $installerPath)
    Write-Host "Install FT_Prog first, then re-run this script to launch FT_Prog.exe directly."
    if (-not $NoLaunch) {
        Start-Process -FilePath $installerPath
    }
} else {
    $downloadUrl = Get-FtProgDownloadUrl
    Write-Warning "FT_Prog.exe was not found locally."
    Write-Host ("Open the official download URL in a browser and install FT_Prog: {0}" -f $downloadUrl)
    if (-not $NoLaunch) {
        Start-Process $downloadUrl
    }
}
