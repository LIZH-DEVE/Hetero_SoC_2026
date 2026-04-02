[CmdletBinding()]
param(
    [string]$Port = "COM9",

    [ValidateSet(115200, 230400)]
    [int]$Baud = 115200,

    [int]$CaptureSeconds = 120,

    [int]$BootLeadSeconds = 20,

    [string]$TargetIp = "192.168.1.20",

    [string]$SourceIp = "192.168.1.11",

    [string]$SdDrive,

    [switch]$Deploy,

    [switch]$AssumeRunning
)

$ErrorActionPreference = "Stop"

# run_ax7020_udp_gateway_shadow_mirror_fastpath_board_check.ps1
$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $workspace
$captureScript = Join-Path $workspace "capture_uart_boot_log.ps1"
$deployScript = Join-Path $workspace "deploy_ax7020_udp_gateway_shadow_mirror_to_sd.ps1"
$controlScript = Join-Path $workspace "udp_crypto_control.py"
$releaseBootBin = Join-Path $workspace "sd_boot\ax7020_udp_gateway_shadow_mirror\BOOT.BIN"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$uartLogPath = Join-Path $repoRoot ("board_uart_boot_{0}_{1}.txt" -f $Baud, $stamp)
$captureStdout = Join-Path $env:TEMP ("shadow_fastpath_capture_stdout_{0}.txt" -f $stamp)
$captureStderr = Join-Path $env:TEMP ("shadow_fastpath_capture_stderr_{0}.txt" -f $stamp)
$aesPayloadHex = "3243f6a8885a308d313198a2e0370734"
$sm4PayloadHex = "0123456789abcdeffedcba9876543210"
$captureProc = $null
$script:ControlSeqId = 0

if (-not (Test-Path $releaseBootBin)) {
    throw "Release BOOT.BIN not found: $releaseBootBin"
}
if (-not (Test-Path $controlScript)) {
    throw "Control helper not found: $controlScript"
}

$expectedHash = (Get-FileHash $releaseBootBin -Algorithm SHA256).Hash.ToUpperInvariant()

function Invoke-ControlCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    Write-Host ("==== {0} ====" -f $Label)
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath "py.exe" `
            -ArgumentList (@("-3", $controlScript) + $Arguments) `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $stdout = @()
        $stderr = @()
        if (Test-Path $stdoutPath) {
            $stdout = @(Get-Content $stdoutPath)
        }
        if (Test-Path $stderrPath) {
            $stderr = @(Get-Content $stderrPath)
        }

        $output = @($stdout + $stderr)
        if ($output) {
            $output | ForEach-Object { Write-Host $_ }
        }

        return [PSCustomObject]@{
            Label = $Label
            Output = $output
            ExitCode = $proc.ExitCode
        }
    }
    finally {
        Remove-Item $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
    }
}

function Invoke-ControlCommandWithRetry {
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [int]$RetryCount = 1,

        [int]$RetryDelaySeconds = 1
    )

    $lastResult = $null
    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        $lastResult = Invoke-ControlCommand -Label $Label -Arguments $Arguments
        if ($lastResult.ExitCode -eq 0) {
            return $lastResult
        }
        if ($attempt -lt $RetryCount) {
            Write-Host ("{0} retry {1}/{2} in {3}s" -f $Label, $attempt, $RetryCount, $RetryDelaySeconds)
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
    return $lastResult
}

function New-SeqArgs {
    $script:ControlSeqId += 1
    return @(
        "--seq-id", "$script:ControlSeqId"
    )
}

function Convert-HexToByteArray {
    param(
        [Parameter(Mandatory)]
        [string]$Hex
    )

    $normalized = $Hex.Replace(" ", "").Replace("_", "")
    if (($normalized.Length -eq 0) -or (($normalized.Length % 2) -ne 0)) {
        throw "Payload hex must be non-empty and have even length"
    }
    $bytes = New-Object byte[] ($normalized.Length / 2)
    for ($idx = 0; $idx -lt $bytes.Length; $idx++) {
        $bytes[$idx] = [Convert]::ToByte($normalized.Substring($idx * 2, 2), 16)
    }
    return $bytes
}

function Send-LiveUdpPacket {
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$PayloadHex,

        [Parameter(Mandatory)]
        [int]$RemotePort
    )

    Write-Host ("==== {0} ====" -f $Label)
    $payload = Convert-HexToByteArray -Hex $PayloadHex
    $client = [System.Net.Sockets.UdpClient]::new(([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($SourceIp), 0)))
    try {
        [void]$client.Send($payload, $payload.Length, $TargetIp, $RemotePort)
        Write-Host ("sent_bytes={0} dst_port={1}" -f $payload.Length, $RemotePort)
    }
    finally {
        $client.Dispose()
    }
}

function Get-ControlValue {
    param(
        [Parameter(Mandatory)]
        [object[]]$Output,

        [Parameter(Mandatory)]
        [string]$Key
    )

    $line = $Output | Where-Object { $_ -match ("^{0}=" -f [regex]::Escape($Key)) } | Select-Object -First 1
    if (-not $line) {
        throw "Missing control output key: $Key"
    }
    return ($line -replace ("^{0}=" -f [regex]::Escape($Key)), "")
}

function Get-UartEvidenceLine {
    param(
        [Parameter(Mandatory)]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$Description
    )

    $line = $Lines | Where-Object { $_ -match $Pattern } | Select-Object -First 1
    if (-not $line) {
        throw "UART log is missing required $Description"
    }
    return $line
}

try {
    if ($Deploy) {
        if (-not $SdDrive) {
            throw "-Deploy requires -SdDrive, for example -SdDrive E:"
        }
        & $deployScript -SdDrive $SdDrive
        $hash = (Get-FileHash (Join-Path $SdDrive "BOOT.BIN") -Algorithm SHA256).Hash.ToUpperInvariant()
        Write-Host ("BOOT.BIN SHA256 = {0}" -f $hash)
        if ($hash -ne $expectedHash) {
            throw "Unexpected BOOT.BIN hash on SD. Expected $expectedHash"
        }
    }

    $captureArgs = @(
        "-ExecutionPolicy", "Bypass",
        "-File", $captureScript,
        "-Port", $Port,
        "-Baud", $Baud,
        "-TimeoutSeconds", $CaptureSeconds,
        "-OutputPath", $uartLogPath
    )

    $captureProc = Start-Process -FilePath "powershell" `
        -ArgumentList $captureArgs `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput $captureStdout `
        -RedirectStandardError $captureStderr

    Write-Host ("UART capture started. Log path: {0}" -f $uartLogPath)
    if ($AssumeRunning) {
        Write-Host "Assuming board is already running; skipping power-cycle prompt and boot wait."
    }
    else {
        Write-Host "Power-cycle the board now: turn power off for 3 seconds, then power it back on."
        Write-Host ("Waiting {0} seconds before sending fastpath traffic..." -f $BootLeadSeconds)
        Start-Sleep -Seconds $BootLeadSeconds
    }

    $globalArgs = @(
        "--ip", $TargetIp,
        "--source-ip", $SourceIp
    )
    $script:ControlGlobalArgs = $globalArgs

    $hello = Invoke-ControlCommandWithRetry -Label "HELLO" -Arguments (
        $globalArgs +
        @("hello")
    ) -RetryCount 10 -RetryDelaySeconds 1
    if ($hello.ExitCode -ne 0) {
        throw "hello failed with exit code $($hello.ExitCode)"
    }

    $sessionId = Get-ControlValue -Output $hello.Output -Key "session_id"
    $bindingId = Get-ControlValue -Output $hello.Output -Key "binding_id"
    $sessionBindingArgs = @(
        "--session-id", $sessionId,
        "--binding-id", $bindingId
    )

    $seqArgs = New-SeqArgs
    $setKey = Invoke-ControlCommand -Label "SET_KEY" -Arguments (
        $globalArgs +
        @("set-key") +
        $sessionBindingArgs +
        $seqArgs +
        @(
            "--algo", "aes",
            "--dual-enable"
        )
    )
    if ($setKey.ExitCode -ne 0) {
        throw "set-key failed with exit code $($setKey.ExitCode)"
    }
    $setKeyReply = Get-ControlValue -Output $setKey.Output -Key "reply_payload_hex"

    Send-LiveUdpPacket -Label "AES" -PayloadHex $aesPayloadHex -RemotePort 4660
    Start-Sleep -Milliseconds 250
    Send-LiveUdpPacket -Label "SM4" -PayloadHex $sm4PayloadHex -RemotePort 4661
    Start-Sleep -Milliseconds 500

    try {
        if (($null -ne $captureProc) -and (-not $captureProc.HasExited)) {
            Wait-Process -Id $captureProc.Id
        }
    }
    catch [System.InvalidOperationException] {
    }
    catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
    }

    $captureOutput = @()
    if (Test-Path $captureStdout) {
        $captureOutput += Get-Content $captureStdout
    }
    if (Test-Path $captureStderr) {
        $captureOutput += Get-Content $captureStderr
    }

    if ($captureOutput.Count -gt 0) {
        Write-Host "==== CAPTURE SCRIPT OUTPUT ===="
        $captureOutput | ForEach-Object { Write-Host $_ }
    }

    if (-not (Test-Path $uartLogPath)) {
        throw "UART log file was not created: $uartLogPath"
    }

    $uartLines = Get-Content $uartLogPath
    $uartText = $uartLines -join [Environment]::NewLine

    $liveAesLine = Get-UartEvidenceLine -Lines $uartLines -Pattern "LIVE_AES PASS" -Description "LIVE_AES PASS line"
    $liveSm4Line = Get-UartEvidenceLine -Lines $uartLines -Pattern "LIVE_SM4 PASS" -Description "LIVE_SM4 PASS line"
    $shadowAesLine = Get-UartEvidenceLine -Lines $uartLines -Pattern "SHADOW_AES PASS" -Description "SHADOW_AES PASS line"
    $shadowSm4Line = Get-UartEvidenceLine -Lines $uartLines -Pattern "SHADOW_SM4 PASS" -Description "SHADOW_SM4 PASS line"
    $fastpathPassLines = @($uartLines | Where-Object { $_ -match "SHADOW_FASTPATH PASS" })
    $fastpathFallbackLines = @($uartLines | Where-Object { $_ -match "SHADOW_FASTPATH FALLBACK" })
    $txcapEvidenceLines = @($uartLines | Where-Object { $_ -match "TXCAP words=" })
    $fastpathHitCountLines = @($uartLines | Where-Object { $_ -match "FASTPATH_HIT_COUNT count=" })
    $fastpathFallbackCountLines = @($uartLines | Where-Object { $_ -match "FASTPATH_FALLBACK_COUNT count=" })

    if ($fastpathPassLines.Count -lt 2) {
        throw "UART log does not show two SHADOW_FASTPATH PASS events"
    }
    if ($fastpathFallbackLines.Count -gt 0) {
        throw ("Fastpath fallback observed in UART log: {0}" -f ($fastpathFallbackLines -join "; "))
    }
    if ($txcapEvidenceLines.Count -lt 2) {
        throw "UART log does not show TXCAP words evidence for both algorithms"
    }
    if ($fastpathHitCountLines.Count -lt 2) {
        throw "UART log does not show FASTPATH_HIT_COUNT for both algorithms"
    }
    if ($fastpathFallbackCountLines.Count -lt 2) {
        throw "UART log does not show FASTPATH_FALLBACK_COUNT for both algorithms"
    }

    $fastpathHitCountMatch = [regex]::Match($fastpathHitCountLines[-1], "FASTPATH_HIT_COUNT count=(\d+)")
    if (-not $fastpathHitCountMatch.Success) {
        throw "Failed to parse FASTPATH_HIT_COUNT from UART log"
    }
    $fastpathHitCount = [uint32]$fastpathHitCountMatch.Groups[1].Value
    if ($fastpathHitCount -lt 2) {
        throw "FASTPATH_HIT_COUNT did not reach 2 after AES and SM4 probes"
    }

    $fastpathFallbackCountMatch = [regex]::Match($fastpathFallbackCountLines[-1], "FASTPATH_FALLBACK_COUNT count=(\d+)")
    if (-not $fastpathFallbackCountMatch.Success) {
        throw "Failed to parse FASTPATH_FALLBACK_COUNT from UART log"
    }
    $fastpathFallbackCount = [uint32]$fastpathFallbackCountMatch.Groups[1].Value
    if ($fastpathFallbackCount -ne 0) {
        throw "FASTPATH_FALLBACK_COUNT is non-zero after normal fastpath traffic"
    }

    Write-Host "==== UART KEY LINES ===="
    Write-Host $liveAesLine
    Write-Host $liveSm4Line
    Write-Host $shadowAesLine
    Write-Host $shadowSm4Line
    $fastpathPassLines | ForEach-Object { Write-Host $_ }

    Write-Host "==== TXCAP EVIDENCE ===="
    $txcapEvidenceLines | ForEach-Object { Write-Host $_ }

    Write-Host "==== CONTROL SUMMARY ===="
    Write-Host ("HELLO session_id={0}" -f $sessionId)
    Write-Host ("HELLO binding_id={0}" -f $bindingId)
    Write-Host ("SET_KEY reply_payload_hex={0}" -f $setKeyReply)
    Write-Host ("FASTPATH_HIT_COUNT={0}" -f $fastpathHitCount)
    Write-Host ("FASTPATH_FALLBACK_COUNT={0}" -f $fastpathFallbackCount)
    if ($uartText -match "LIVE_CTRL PASS") {
        $uartLines | Where-Object { $_ -match "LIVE_CTRL PASS" } | Select-Object -First 4 | ForEach-Object { Write-Host $_ }
    }

    Write-Host "fastpath board check completed"
}
finally {
    if ($captureProc -and -not $captureProc.HasExited) {
        Stop-Process -Id $captureProc.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $captureStdout, $captureStderr -ErrorAction SilentlyContinue
}
