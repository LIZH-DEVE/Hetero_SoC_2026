[CmdletBinding()]
param(
    [ValidateSet("capture", "start", "stop")]
    [string]$Action = "capture",

    [int]$DurationSeconds = 15,

    [string]$OutputBase = "board_capture",

    [string]$OutputDir = "."
)

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PktMonPath {
    $command = Get-Command PktMon.exe -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "PktMon.exe was not found in PATH."
    }
    return $command.Source
}

function Start-Capture {
    param(
        [string]$PktMon,
        [string]$EtlPath
    )

    & $PktMon stop | Out-Null
    & $PktMon start --capture --comp nics --pkt-size 0 --file-name $EtlPath --file-size 1024 --log-mode memory
    if ($LASTEXITCODE -ne 0) {
        throw "PktMon start failed with exit code $LASTEXITCODE"
    }
}

function Stop-Capture {
    param(
        [string]$PktMon,
        [string]$EtlPath,
        [string]$PcapPath
    )

    & $PktMon stop
    if ($LASTEXITCODE -ne 0) {
        throw "PktMon stop failed with exit code $LASTEXITCODE"
    }

    & $PktMon etl2pcap $EtlPath --out $PcapPath
    if ($LASTEXITCODE -ne 0) {
        throw "PktMon etl2pcap failed with exit code $LASTEXITCODE"
    }
}

$pktMon = Get-PktMonPath
$outputPath = (Resolve-Path $OutputDir).Path
$etlPath = Join-Path $outputPath "$OutputBase.etl"
$pcapPath = Join-Path $outputPath "$OutputBase.pcapng"

if (-not (Test-IsAdministrator)) {
    throw "PktMon capture requires an elevated PowerShell session (Run as Administrator)."
}

switch ($Action) {
    "start" {
        Start-Capture -PktMon $pktMon -EtlPath $etlPath
        Write-Host "PktMon capture started."
        Write-Host "ETL:  $etlPath"
        Write-Host "PCAP: $pcapPath"
    }

    "stop" {
        Stop-Capture -PktMon $pktMon -EtlPath $etlPath -PcapPath $pcapPath
        Write-Host "PktMon capture stopped."
        Write-Host "ETL:  $etlPath"
        Write-Host "PCAP: $pcapPath"
    }

    "capture" {
        Start-Capture -PktMon $pktMon -EtlPath $etlPath
        Start-Sleep -Seconds $DurationSeconds
        Stop-Capture -PktMon $pktMon -EtlPath $etlPath -PcapPath $pcapPath
        Write-Host "PktMon capture completed."
        Write-Host "ETL:  $etlPath"
        Write-Host "PCAP: $pcapPath"
    }
}
