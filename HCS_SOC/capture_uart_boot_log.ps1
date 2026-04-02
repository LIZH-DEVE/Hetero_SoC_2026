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
$bytes = [System.Collections.Generic.List[byte]]::new()
$serial = $null
$serialOpenStopwatch = $null

function New-UartSerialPort {
    param(
        [Parameter(Mandatory)]
        [string]$PortName,

        [Parameter(Mandatory)]
        [int]$PortBaud,

        [Parameter(Mandatory)]
        [System.Text.Encoding]$PortEncoding
    )

    $port = [System.IO.Ports.SerialPort]::new($PortName, $PortBaud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
    $port.Handshake = [System.IO.Ports.Handshake]::None
    $port.ReadTimeout = 200
    $port.WriteTimeout = 200
    $port.DtrEnable = $false
    $port.RtsEnable = $false
    $port.Encoding = $PortEncoding
    return $port
}

function Close-UartSerialPort {
    param(
        [ref]$SerialRef
    )

    if (($null -ne $SerialRef.Value) -and $SerialRef.Value.IsOpen) {
        $SerialRef.Value.Close()
    }
    if ($null -ne $SerialRef.Value) {
        $SerialRef.Value.Dispose()
        $SerialRef.Value = $null
    }
}

try {
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
        if (($null -eq $serial) -or (-not $serial.IsOpen)) {
            Close-UartSerialPort -SerialRef ([ref]$serial)
            $serialOpenStopwatch = $null
            try {
                $serial = New-UartSerialPort -PortName $Port -PortBaud $Baud -PortEncoding $encoding
                $serial.Open()
                $serial.DiscardInBuffer()
                $serial.DiscardOutBuffer()
                $serialOpenStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                Start-Sleep -Milliseconds 200
            }
            catch {
                Close-UartSerialPort -SerialRef ([ref]$serial)
                $serialOpenStopwatch = $null
                Start-Sleep -Milliseconds 100
                continue
            }
        }

        # After a real power cycle, Windows can leave an apparently-open COM handle
        # attached to a stale device endpoint. Until we see the first byte, periodically
        # reopen the port so we can latch onto the re-enumerated boot stream.
        if (($bytes.Count -eq 0) -and $serialOpenStopwatch -and ($serialOpenStopwatch.Elapsed.TotalSeconds -ge 1.0)) {
            Close-UartSerialPort -SerialRef ([ref]$serial)
            $serialOpenStopwatch = $null
            Start-Sleep -Milliseconds 100
            continue
        }

        try {
            $available = $serial.BytesToRead
            if ($available -gt 0) {
                $chunk = New-Object byte[] $available
                $read = $serial.Read($chunk, 0, $available)
                for ($i = 0; $i -lt $read; ++$i) {
                    [void]$bytes.Add($chunk[$i])
                }
            }
            else {
                Start-Sleep -Milliseconds 50
            }
        }
        catch [System.TimeoutException] {
        }
        catch [System.InvalidOperationException] {
            Close-UartSerialPort -SerialRef ([ref]$serial)
            $serialOpenStopwatch = $null
            Start-Sleep -Milliseconds 100
        }
        catch [System.IO.IOException] {
            Close-UartSerialPort -SerialRef ([ref]$serial)
            $serialOpenStopwatch = $null
            Start-Sleep -Milliseconds 100
        }
        catch [System.UnauthorizedAccessException] {
            Close-UartSerialPort -SerialRef ([ref]$serial)
            $serialOpenStopwatch = $null
            Start-Sleep -Milliseconds 100
        }
    }
} finally {
    Close-UartSerialPort -SerialRef ([ref]$serial)
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
