[CmdletBinding()]
param(
    [string]$Port = "COM9",

    [ValidateSet(115200, 230400)]
    [int]$Baud = 115200,

    [switch]$LockBaud,

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
    $outputDir = Join-Path $repoRoot "doc\reports\board_uart"
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    $OutputPath = Join-Path $outputDir ("board_uart_boot_{0}_{1}.txt" -f $Baud, $stamp)
}

$encoding = [System.Text.Encoding]::GetEncoding("ISO-8859-1")
$bytes = [System.Collections.Generic.List[byte]]::new()
$serial = $null
$serialOpenStopwatch = $null
$printableThreshold = 0.85
$programProc = $null
$programLaunchStarted = $false
$programStdoutPath = $null
$programStderrPath = $null
$programExitStopwatch = $null

function Get-UartBaudCandidates {
    param(
        [Parameter(Mandatory)]
        [int]$PreferredBaud,

        [switch]$LockBaud
    )

    if ($LockBaud) {
        return @($PreferredBaud)
    }

    $ordered = [System.Collections.Generic.List[int]]::new()
    [void]$ordered.Add($PreferredBaud)
    foreach ($candidate in @(115200, 230400)) {
        if (-not $ordered.Contains($candidate)) {
            [void]$ordered.Add($candidate)
        }
    }
    return $ordered.ToArray()
}

function Test-UartCaptureLooksSane {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IList]$Data
    )

    if ($Data.Count -le 0) {
        return $false
    }

    $sampleCount = [Math]::Min($Data.Count, 256)
    $printableCount = 0
    for ($index = 0; $index -lt $sampleCount; ++$index) {
        $value = [int]$Data[$index]
        if (
            ($value -eq 0x09) -or
            ($value -eq 0x0A) -or
            ($value -eq 0x0D) -or
            (($value -ge 0x20) -and ($value -le 0x7E))
        ) {
            $printableCount += 1
        }
    }

    $printableRatio = [double]$printableCount / [double]$sampleCount
    return ($printableRatio -ge $printableThreshold)
}

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

function Normalize-PathEnvironment {
    $processEnv = [System.Environment]::GetEnvironmentVariables('Process')
    if ($processEnv.Contains('Path') -and $processEnv.Contains('PATH')) {
        [System.Environment]::SetEnvironmentVariable('PATH', $null, 'Process')
    }
}

function Resolve-CaptureProgrammerXsctPath {
    param([string]$ConfiguredPath)

    if ($ConfiguredPath) {
        return (Resolve-Path $ConfiguredPath).Path
    }

    $candidates = @(
        "D:\Xilinx\Vitis\2024.1\bin\xsct.bat",
        "C:\Xilinx\Vitis\2024.1\bin\xsct.bat"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "xsct.bat was not found. Pass -XsdbPath explicitly."
}

try {
    if ($ProgramBoard) {
        $programmer = Join-Path $workspace "run_ax7020_udp_gateway_shadow_mirror_jtag.ps1"
        $programmerXsctPath = Resolve-CaptureProgrammerXsctPath -ConfiguredPath $XsdbPath
        $programStdoutPath = [System.IO.Path]::GetTempFileName()
        $programStderrPath = [System.IO.Path]::GetTempFileName()
    }

    $baudCandidates = Get-UartBaudCandidates -PreferredBaud $Baud -LockBaud:$LockBaud
    $currentBaudIndex = 0
    $activeBaud = $baudCandidates[$currentBaudIndex]
    $baudLocked = $false

    $deadline = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        if ($ProgramBoard) {
            $maxProgramCaptureSeconds = [Math]::Max(([double]$TimeoutSeconds) + 180.0, 240.0)
            if ($deadline.Elapsed.TotalSeconds -ge $maxProgramCaptureSeconds) {
                break
            }
        }
        elseif ($deadline.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            break
        }

        if (($null -eq $serial) -or (-not $serial.IsOpen)) {
            Close-UartSerialPort -SerialRef ([ref]$serial)
            $serialOpenStopwatch = $null
            try {
                $activeBaud = $baudCandidates[$currentBaudIndex]
                $serial = New-UartSerialPort -PortName $Port -PortBaud $activeBaud -PortEncoding $encoding
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

        if ($ProgramBoard -and (-not $programLaunchStarted) -and $serial -and $serial.IsOpen) {
            $programArgs = @(
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                $programmer,
                "-XsctPath",
                $programmerXsctPath
            )
            Normalize-PathEnvironment
            $programProc = Start-Process -FilePath "powershell" `
                -ArgumentList $programArgs `
                -PassThru `
                -WindowStyle Hidden `
                -RedirectStandardOutput $programStdoutPath `
                -RedirectStandardError $programStderrPath
            $programLaunchStarted = $true
        }

        if ($ProgramBoard -and $programLaunchStarted -and $programProc -and $programProc.HasExited) {
            if ($null -eq $programExitStopwatch) {
                $programExitStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            }
            elseif ($programExitStopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                break
            }
        }

        # After a real power cycle, Windows can leave an apparently-open COM handle
        # attached to a stale device endpoint. Until we see the first byte, periodically
        # reopen the port so we can latch onto the re-enumerated boot stream.
        # Do not treat an empty probe as evidence of a wrong baud rate: on SD cold boot
        # the first printable bytes can legitimately arrive well after one second.
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

                if (-not $baudLocked) {
                    $readyForSanityCheck = ($bytes.Count -ge 48)
                    if ((-not $readyForSanityCheck) -and $serialOpenStopwatch) {
                        $readyForSanityCheck = ($serialOpenStopwatch.Elapsed.TotalSeconds -ge 0.6)
                    }

                    if ($readyForSanityCheck) {
                        if (Test-UartCaptureLooksSane -Data $bytes) {
                            $baudLocked = $true
                        }
                        elseif ($currentBaudIndex -lt ($baudCandidates.Count - 1)) {
                            Write-Host ("Switching UART capture baud from {0} to {1} after gibberish probe." -f $activeBaud, $baudCandidates[$currentBaudIndex + 1])
                            $bytes.Clear()
                            $currentBaudIndex += 1
                            Close-UartSerialPort -SerialRef ([ref]$serial)
                            $serialOpenStopwatch = $null
                            Start-Sleep -Milliseconds 100
                            continue
                        }
                        else {
                            $baudLocked = $true
                        }
                    }
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
    if (($null -ne $programProc) -and (-not $programProc.HasExited)) {
        try {
            Wait-Process -Id $programProc.Id
        }
        catch [System.InvalidOperationException] {
        }
        catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
        }
    }
}

[System.IO.File]::WriteAllBytes($OutputPath, $bytes.ToArray())
$captureLooksSane = Test-UartCaptureLooksSane -Data $bytes
$sampleCount = [Math]::Min($bytes.Count, 256)
$printableCount = 0
if ($sampleCount -gt 0) {
    for ($index = 0; $index -lt $sampleCount; ++$index) {
        $value = [int]$bytes[$index]
        if (
            ($value -eq 0x09) -or
            ($value -eq 0x0A) -or
            ($value -eq 0x0D) -or
            (($value -ge 0x20) -and ($value -le 0x7E))
        ) {
            $printableCount += 1
        }
    }
}
$printableRatio = if ($sampleCount -gt 0) { [double]$printableCount / [double]$sampleCount } else { 0.0 }
$preview = $encoding.GetString($bytes.ToArray())

$programOutput = @()
if ($programStdoutPath -and (Test-Path $programStdoutPath)) {
    $programOutput += Get-Content $programStdoutPath
}
if ($programStderrPath -and (Test-Path $programStderrPath)) {
    $programOutput += Get-Content $programStderrPath
}
if ($programOutput.Count -gt 0) {
    Write-Host "==== PROGRAM SCRIPT OUTPUT ===="
    $programOutput | ForEach-Object { Write-Host $_ }
}
if ($programStdoutPath) {
    Remove-Item $programStdoutPath -ErrorAction SilentlyContinue
}
if ($programStderrPath) {
    Remove-Item $programStderrPath -ErrorAction SilentlyContinue
}
if ($ProgramBoard -and $programProc) {
    $programProc.Refresh()
    $programExitCode = $programProc.ExitCode
    $programSucceeded = ($programOutput -match "JTAG_RUN_DONE")
    if (-not $programSucceeded) {
        throw "ProgramBoard runner did not report JTAG_RUN_DONE"
    }
    if (($null -ne $programExitCode) -and ($programExitCode -ne 0)) {
        throw "ProgramBoard runner exited with code $programExitCode"
    }
}

Write-Host ("UART capture saved to {0}" -f $OutputPath)
Write-Host ("Port={0} PreferredBaud={1} DetectedBaud={2} Bytes={3} CaptureLooksSane={4} PrintableRatio={5}" -f $Port, $Baud, $activeBaud, $bytes.Count, $captureLooksSane, ([string]::Format("{0:F3}", $printableRatio)))
if (($preview.Length -gt 0) -and $captureLooksSane) {
    Write-Host "Preview:"
    Write-Host $preview
}
elseif ($preview.Length -gt 0) {
    Write-Warning "Captured UART bytes did not decode as sane printable text; treat UART evidence as unreliable."
} else {
    Write-Warning "No UART data captured."
}
