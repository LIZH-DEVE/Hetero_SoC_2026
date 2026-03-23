[CmdletBinding()]
param(
    [string]$Port = "COM9",

    [ValidateSet(115200, 230400)]
    [int]$Baud = 115200,

    [int]$TimeoutSeconds = 8,

    [string]$OutputPath,

    [switch]$ProgramBoard,

    [string]$XsdbPath
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $workspace

if (-not $OutputPath) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputPath = Join-Path $repoRoot ("board_uart_boot_{0}_{1}.txt" -f $Baud, $stamp)
}

$encoding = [System.Text.Encoding]::GetEncoding("ISO-8859-1")
$serial = [System.IO.Ports.SerialPort]::new($Port, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.ReadTimeout = 200
$serial.WriteTimeout = 200
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$serial.Encoding = $encoding

$bytes = [System.Collections.Generic.List[byte]]::new()

try {
    $serial.Open()
    $serial.DiscardInBuffer()
    $serial.DiscardOutBuffer()
    Start-Sleep -Milliseconds 200

    if ($ProgramBoard) {
        $smokeArgs = @{
            Action = "program_and_status"
        }
        if ($XsdbPath) {
            $smokeArgs["XsdbPath"] = $XsdbPath
        }
        & (Join-Path $workspace "run_board_smoke.ps1") @smokeArgs
    }

    $deadline = [System.Diagnostics.Stopwatch]::StartNew()
    while ($deadline.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $available = $serial.BytesToRead
        if ($available -gt 0) {
            $chunk = New-Object byte[] $available
            $read = $serial.Read($chunk, 0, $available)
            for ($i = 0; $i -lt $read; ++$i) {
                [void]$bytes.Add($chunk[$i])
            }
        } else {
            Start-Sleep -Milliseconds 50
        }
    }
} finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
    $serial.Dispose()
}

[System.IO.File]::WriteAllBytes($OutputPath, $bytes.ToArray())
$preview = $encoding.GetString($bytes.ToArray())

Write-Host ("UART capture saved to {0}" -f $OutputPath)
Write-Host ("Port={0} Baud={1} Bytes={2}" -f $Port, $Baud, $bytes.Count)
if ($preview.Length -gt 0) {
    Write-Host "Preview:"
    Write-Host $preview
} else {
    Write-Warning "No UART data captured."
}
