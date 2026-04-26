[CmdletBinding()]
param(
    [string]$Port = "COM9",

    [ValidateSet(115200, 230400)]
    [int]$Baud = 115200,

    [int]$DurationMinutes = 30,

    [int]$CycleIntervalSeconds = 15,

    [int]$BootLeadSeconds = 20,

    [string]$TargetIp = "192.168.1.20",

    [string]$SourceIp = "192.168.1.11",

    [string]$SdDrive,

    [switch]$Deploy,

    [switch]$AssumeRunning,

    [switch]$ColdStart
)

$ErrorActionPreference = "Stop"

# run_ax7020_udp_gateway_shadow_mirror_soak_check.ps1
$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $workspace
$captureScript = Join-Path $workspace "capture_uart_boot_log.ps1"
$deployScript = Join-Path $workspace "deploy_ax7020_udp_gateway_shadow_mirror_to_sd.ps1"
$controlScript = Join-Path $workspace "udp_crypto_control.py"
$sendUdpScript = Join-Path $workspace "send_udp_crypto_test.py"
$releaseBootBin = Join-Path $workspace "sd_boot\ax7020_udp_gateway_shadow_mirror\BOOT.BIN"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportDir = Join-Path $repoRoot ("doc\reports\board_soak\shadow_mirror_{0}" -f $stamp)
$reportJsonPath = Join-Path $reportDir "soak_report.json"
$reportMarkdownPath = Join-Path $reportDir "soak_summary.md"
$uartLogPath = Join-Path $repoRoot ("board_uart_boot_{0}_{1}.txt" -f $Baud, $stamp)
$bootUartLogPath = Join-Path $reportDir "cold_start_boot_uart.txt"
$captureStdout = Join-Path $env:TEMP ("shadow_soak_capture_stdout_{0}.txt" -f $stamp)
$captureStderr = Join-Path $env:TEMP ("shadow_soak_capture_stderr_{0}.txt" -f $stamp)
$bootCaptureStdout = Join-Path $env:TEMP ("shadow_soak_boot_capture_stdout_{0}.txt" -f $stamp)
$bootCaptureStderr = Join-Path $env:TEMP ("shadow_soak_boot_capture_stderr_{0}.txt" -f $stamp)
$script:ControlSeqId = 0
$script:ControlGlobalArgs = @()
$captureProc = $null
$bootCaptureProc = $null
$expectedHash = $null
$resultStatus = "FAIL"
$failureReason = $null
$cycleResults = New-Object System.Collections.Generic.List[object]
$badUartEvidence = New-Object System.Collections.Generic.List[string]
$softUartWarnings = New-Object System.Collections.Generic.List[string]
$captureOutput = @()
$uartText = ""
$bootUartText = ""
$captureTimeoutSeconds = [Math]::Max(($DurationMinutes * 60) + 120, 120)
$bootCaptureTimeoutSeconds = [Math]::Max(($BootLeadSeconds + 5), 5)
$blockedSourcePort = 54060
$aesPayloadHex = "3243f6a8885a308d313198a2e0370734"
$sm4PayloadHex = "0123456789abcdeffedcba9876543210"
$startTime = Get-Date
$endTime = $null
$deadline = $startTime.AddMinutes($DurationMinutes)
$sessionId = $null
$bindingId = $null
$sessionBindingArgs = @()
$baselineStatus = $null
$currentStatus = $null
$aesExpectedReplyHex = $null
$sm4ExpectedReplyHex = $null
$aclProbeCount = 0
$replayProbeCount = 0
$aesProbeCount = 0
$sm4ProbeCount = 0
$script:BootEvidenceFound = $false
$script:BootEvidenceLines = @()
$script:BootEvidenceMode = "none"
$script:FirstControlSuccessUtc = $null
$script:FirstDataSuccessUtc = $null
$pythonExe = (Get-Command python.exe -ErrorAction Stop).Source
$bootEvidencePatterns = @(
    "UDP gateway shadow mirror image",
    "UDP crypto gateway started @ ports 4660(AES) 4661(SM4) 4662(CTRL)",
    "Board IP: 192.168.1.20"
)

if (-not (Test-Path $releaseBootBin)) {
    throw "Release BOOT.BIN not found: $releaseBootBin"
}
if (-not (Test-Path $controlScript)) {
    throw "Control helper not found: $controlScript"
}
if (-not (Test-Path $sendUdpScript)) {
    throw "UDP data-plane helper not found: $sendUdpScript"
}
if ($ColdStart -and $AssumeRunning) {
    throw "-ColdStart cannot be combined with -AssumeRunning"
}

$expectedHash = (Get-FileHash $releaseBootBin -Algorithm SHA256).Hash.ToUpperInvariant()
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

function Normalize-PathEnvironment {
    $processEnv = [System.Environment]::GetEnvironmentVariables('Process')
    if ($processEnv.Contains('Path') -and $processEnv.Contains('PATH')) {
        [System.Environment]::SetEnvironmentVariable('PATH', $null, 'Process')
    }
}

function Start-UartCaptureProcess {
    param(
        [Parameter(Mandatory)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [string]$StdoutPath,

        [Parameter(Mandatory)]
        [string]$StderrPath
    )

    $captureArgs = @(
        "-ExecutionPolicy", "Bypass",
        "-File", $captureScript,
        "-Port", $Port,
        "-Baud", $Baud,
        "-TimeoutSeconds", $TimeoutSeconds,
        "-OutputPath", $OutputPath
    )

    Normalize-PathEnvironment
    return Start-Process -FilePath "powershell" `
        -ArgumentList $captureArgs `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput $StdoutPath `
        -RedirectStandardError $StderrPath
}

function Get-CaptureOutputLines {
    param(
        [Parameter(Mandatory)]
        [string]$StdoutPath,

        [Parameter(Mandatory)]
        [string]$StderrPath
    )

    $lines = @()
    if (Test-Path $StdoutPath) {
        $lines += Get-Content $StdoutPath
    }
    if (Test-Path $StderrPath) {
        $lines += Get-Content $StderrPath
    }
    return @($lines)
}

function Invoke-PythonCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [string]$WorkingDirectory = $workspace
    )

    Write-Host ("==== {0} ====" -f $Label)
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $pythonExe `
            -ArgumentList $Arguments `
            -WorkingDirectory $WorkingDirectory `
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

function Invoke-ControlCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    return Invoke-PythonCommand -Label $Label -Arguments (@($controlScript) + $Arguments) -WorkingDirectory $workspace
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

function New-ControlArguments {
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [string[]]$PreCommandArgs = @(),

        [string[]]$SessionBindingArgs = @(),

        [string[]]$CommandArgs = @()
    )

    if (-not $script:ControlGlobalArgs -or $script:ControlGlobalArgs.Count -eq 0) {
        throw "Control global arguments were not initialized"
    }

    return @(
        $script:ControlGlobalArgs +
        $PreCommandArgs +
        @($Command) +
        $SessionBindingArgs +
        $CommandArgs
    )
}

function New-SeqArgs {
    $script:ControlSeqId += 1
    return @(
        "--seq-id", "$script:ControlSeqId"
    )
}

function Get-ControlValue {
    param(
        [object[]]$Output,
        [string]$Key
    )

    $line = $Output | Where-Object { $_ -match ("^{0}=" -f [regex]::Escape($Key)) } | Select-Object -First 1
    if (-not $line) {
        throw "Missing control output key: $Key"
    }
    return ($line -replace ("^{0}=" -f [regex]::Escape($Key)), "")
}

function Get-StatusSnapshot {
    param(
        [Parameter(Mandatory)]
        [object[]]$Output
    )

    return [PSCustomObject]@{
        binding_id = [uint32](Get-ControlValue -Output $Output -Key "binding_id")
        session_id = [uint32](Get-ControlValue -Output $Output -Key "session_id")
        authorized_mask = [uint32](Get-ControlValue -Output $Output -Key "authorized_mask")
        locked = [uint32](Get-ControlValue -Output $Output -Key "locked")
        rx_ctrl_ok = [uint32](Get-ControlValue -Output $Output -Key "rx_ctrl_ok")
        rx_data_ok = [uint32](Get-ControlValue -Output $Output -Key "rx_data_ok")
        tx_ok = [uint32](Get-ControlValue -Output $Output -Key "tx_ok")
        drop_invalid = [uint32](Get-ControlValue -Output $Output -Key "drop_invalid")
        drop_unauthorized = [uint32](Get-ControlValue -Output $Output -Key "drop_unauthorized")
        drop_replay = [uint32](Get-ControlValue -Output $Output -Key "drop_replay")
        bind_fail = [uint32](Get-ControlValue -Output $Output -Key "bind_fail")
        lock_events = [uint32](Get-ControlValue -Output $Output -Key "lock_events")
        crypto_timeout = [uint32](Get-ControlValue -Output $Output -Key "crypto_timeout")
        crypto_fail = [uint32](Get-ControlValue -Output $Output -Key "crypto_fail")
    }
}

function Assert-HealthyStatus {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Current,

        [Parameter(Mandatory)]
        [pscustomobject]$Previous,

        [Parameter(Mandatory)]
        [string]$Context
    )

    if ($Current.locked -ne 0) {
        throw ("{0}: expected locked=0, got {1}" -f $Context, $Current.locked)
    }
    if (($Current.authorized_mask -band 0x3) -ne 0x3) {
        throw ("{0}: expected authorized_mask to include AES and SM4, got {1}" -f $Context, $Current.authorized_mask)
    }
    if ($Current.bind_fail -gt $Previous.bind_fail) {
        throw ("{0}: bind_fail grew unexpectedly ({1} -> {2})" -f $Context, $Previous.bind_fail, $Current.bind_fail)
    }
    if ($Current.crypto_timeout -gt $Previous.crypto_timeout) {
        throw ("{0}: crypto_timeout grew unexpectedly ({1} -> {2})" -f $Context, $Previous.crypto_timeout, $Current.crypto_timeout)
    }
    if ($Current.crypto_fail -gt $Previous.crypto_fail) {
        throw ("{0}: crypto_fail grew unexpectedly ({1} -> {2})" -f $Context, $Previous.crypto_fail, $Current.crypto_fail)
    }
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

function Send-TestUdpPacket {
    param(
        [Parameter(Mandatory)]
        [int]$LocalPort,

        [Parameter(Mandatory)]
        [int]$RemotePort,

        [string]$PayloadHex = "000102030405060708090A0B0C0D0E0F"
    )

    $payload = Convert-HexToByteArray -Hex $PayloadHex
    $client = [System.Net.Sockets.UdpClient]::new(([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($SourceIp), $LocalPort)))
    $client.Client.ReceiveTimeout = 750
    try {
        [void]$client.Send($payload, $payload.Length, $TargetIp, $RemotePort)
        $remoteEndpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        try {
            [void]$client.Receive([ref]$remoteEndpoint)
            return $true
        }
        catch [System.Net.Sockets.SocketException] {
            return $false
        }
    }
    finally {
        $client.Dispose()
    }
}

function Get-BindingAwareExpectedReplyHex {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("aes", "sm4")]
        [string]$Algo,

        [Parameter(Mandatory)]
        [string]$BindingId,

        [Parameter(Mandatory)]
        [string]$PayloadHex
    )

    $sendToolDir = Split-Path -Parent $sendUdpScript
    $pythonCode = @"
import binascii
import sys
sys.path.insert(0, r"$sendToolDir")
from Crypto.Cipher import AES
import sm4_reference
import udp_crypto_control as ctrl

algo = sys.argv[1]
binding_id = int(sys.argv[2], 0)
payload = binascii.unhexlify(sys.argv[3].strip())
user_key = ctrl.default_user_key(algo)
effective_key = ctrl.derive_effective_key(user_key, binding_id, ctrl.algo_to_id(algo))
if algo == "sm4":
    reply = sm4_reference.ecb_encrypt(effective_key, payload)
else:
    cipher = AES.new(effective_key, AES.MODE_ECB)
    reply = b"".join(cipher.encrypt(payload[i:i + 16]) for i in range(0, len(payload), 16))
sys.stdout.write(reply.hex())
"@
    $helperPath = Join-Path $env:TEMP ("shadow_expected_reply_{0}.py" -f ([guid]::NewGuid().ToString("N")))
    Set-Content -Path $helperPath -Value $pythonCode -Encoding ASCII
    try {
        $result = Invoke-PythonCommand -Label ("EXPECTED_{0}" -f $Algo.ToUpperInvariant()) -Arguments @(
            $helperPath,
            $Algo,
            $BindingId,
            $PayloadHex
        ) -WorkingDirectory $sendToolDir
    }
    finally {
        Remove-Item $helperPath -ErrorAction SilentlyContinue
    }
    if ($result.ExitCode -ne 0) {
        throw ("Failed to derive binding-aware expected reply for {0}: exit code {1}" -f $Algo, $result.ExitCode)
    }
    $replyHex = ($result.Output | Where-Object { $_ -match '^[0-9a-fA-F]+$' } | Select-Object -Last 1)
    if (-not $replyHex) {
        throw ("Expected reply helper did not emit hex for {0}" -f $Algo)
    }
    return $replyHex.ToLowerInvariant()
}

function Invoke-DataProbe {
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [ValidateSet("aes", "sm4")]
        [string]$Algo,

        [Parameter(Mandatory)]
        [string]$PayloadHex,

        [string]$ExpectedReplyHex
    )

    $arguments = @(
        $sendUdpScript,
        "--algo", $Algo,
        "--ip", $TargetIp,
        "--source-ip", $SourceIp,
        "--timeout", "2",
        "--retries", "2",
        "--retry-delay", "0.25",
        "--summary-only",
        "--skip-control-session",
        "--expect-any-reply",
        "--payload-hex", $PayloadHex
    )
    if ($ExpectedReplyHex) {
        $arguments += @("--expected-reply-hex", $ExpectedReplyHex)
    }

    $result = Invoke-PythonCommand -Label $Label -Arguments $arguments -WorkingDirectory (Split-Path -Parent $sendUdpScript)

    if ($result.ExitCode -ne 0) {
        throw ("{0}: data probe helper failed with exit code {1}" -f $Label, $result.ExitCode)
    }
    if (-not ($result.Output -contains "result=PASS")) {
        throw ("{0}: data probe helper did not report PASS" -f $Label)
    }
    if ($ExpectedReplyHex -and (-not ($result.Output -contains "expected_match=1"))) {
        throw ("{0}: data probe helper did not confirm expected_match=1" -f $Label)
    }
    if (-not $script:FirstDataSuccessUtc) {
        $script:FirstDataSuccessUtc = (Get-Date).ToUniversalTime().ToString("o")
    }
    return $result
}

function Get-UartText {
    param(
        [string]$Path = $uartLogPath
    )

    if (-not (Test-Path $Path)) {
        return ""
    }
    return (Get-Content $Path -Raw)
}

function Get-BootEvidenceSnapshot {
    param(
        [Parameter(Mandatory)]
        [string]$UartText
    )

    $localUartText = $UartText
    $uartLines = $localUartText -split "`r?`n"
    $matchedLines = @()
    $missingLines = @()

    foreach ($pattern in $bootEvidencePatterns) {
        $matchLine = $uartLines |
            Where-Object { $_ -and ($_.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) } |
            Select-Object -First 1
        if ($matchLine) {
            $matchedLines += $matchLine.Trim()
        }
        else {
            $missingLines += $pattern
        }
    }

    return [PSCustomObject]@{
        Found = ($missingLines.Count -eq 0)
        Matched = @($matchedLines)
        Missing = @($missingLines)
    }
}

function Confirm-ColdStartBootEvidence {
    if (-not $ColdStart) {
        return
    }

    $script:BootEvidenceFound = $false
    $script:BootEvidenceLines = @()
    $script:BootEvidenceMode = "none"

    if (-not $bootCaptureProc) {
        throw "ColdStart mode expected a boot UART capture process, but none was started."
    }

    Write-Host "ColdStart mode: power-cycle the board now. Turn power off for 3 seconds, then power it back on."
    Write-Host ("Waiting {0} seconds before validating cold-start boot evidence..." -f $BootLeadSeconds)
    Start-Sleep -Seconds $BootLeadSeconds

    Wait-Process -Id $bootCaptureProc.Id -ErrorAction SilentlyContinue
    $captureOutput += Get-CaptureOutputLines -StdoutPath $bootCaptureStdout -StderrPath $bootCaptureStderr

    $bootUartText = Get-UartText -Path $bootUartLogPath
    if (-not $bootUartText) {
        [void]$softUartWarnings.Add("Cold-start UART boot capture was empty; will require control/data fallback evidence.")
        return
    }

    Test-UartHardFailures -Context "cold-start boot-check" -UartTextOverride $bootUartText

    $snapshot = Get-BootEvidenceSnapshot -UartText $bootUartText
    $script:BootEvidenceFound = [bool]$snapshot.Found
    $script:BootEvidenceLines = @($snapshot.Matched)
    if (-not $snapshot.Found) {
        [void]$softUartWarnings.Add(("Cold-start UART boot capture missed required boot lines: {0}" -f ($snapshot.Missing -join ", ")))
        return
    }
    $script:BootEvidenceMode = "uart_boot"

    Write-Host "==== COLD START BOOT EVIDENCE ===="
    $script:BootEvidenceLines | ForEach-Object { Write-Host $_ }
}

function Finalize-ColdStartEvidence {
    if (-not $ColdStart) {
        return
    }

    if ($script:BootEvidenceFound) {
        return
    }

    if ($script:FirstControlSuccessUtc -and $script:FirstDataSuccessUtc) {
        $script:BootEvidenceFound = $true
        $script:BootEvidenceMode = "control_data_after_manual_power_cycle"
        $script:BootEvidenceLines = @(
            ("fallback control evidence: {0}" -f $script:FirstControlSuccessUtc),
            ("fallback data evidence: {0}" -f $script:FirstDataSuccessUtc)
        )
        Write-Host "==== COLD START FALLBACK EVIDENCE ===="
        $script:BootEvidenceLines | ForEach-Object { Write-Host $_ }
        return
    }

    throw "Cold-start soak missing both UART boot evidence and post-boot control/data fallback evidence."
}

function Test-UartHardFailures {
    param(
        [string]$Context,

        [string]$UartTextOverride
    )

    $localUartText = $UartTextOverride
    if (-not $localUartText) {
        $localUartText = Get-UartText
    }
    if (-not $localUartText) {
        return
    }

    $patterns = @(
        "shadow compare fail",
        "SHADOW_FASTPATH FALLBACK",
        "poll timeout",
        "HALTED",
        "WAIT_BLOCK_DONE timeout"
    )

    foreach ($pattern in $patterns) {
        if ($localUartText.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $evidence = "{0}: {1}" -f $Context, $pattern
            [void]$badUartEvidence.Add($evidence)
            throw ("UART hard failure detected ({0})" -f $evidence)
        }
    }
}

function Invoke-AclMicroProbe {
    param(
        [Parameter(Mandatory)]
        [int]$CycleNumber
    )

    $probeTag = "CYCLE_{0:000}_ACL" -f $CycleNumber

    $seqArgs = New-SeqArgs
    $aclClearBefore = Invoke-ControlCommand -Label ("{0}_CLEAR_BEFORE" -f $probeTag) -Arguments (
        New-ControlArguments -Command "acl-clear" -SessionBindingArgs $sessionBindingArgs -CommandArgs $seqArgs
    )
    if ($aclClearBefore.ExitCode -ne 0) {
        throw ("{0}: acl-clear before failed with exit code {1}" -f $probeTag, $aclClearBefore.ExitCode)
    }

    $seqArgs = New-SeqArgs
    $aclWrite = Invoke-ControlCommand -Label ("{0}_WRITE" -f $probeTag) -Arguments (
        New-ControlArguments -Command "acl-write" -SessionBindingArgs $sessionBindingArgs -CommandArgs (
            $seqArgs +
            @(
                "--src-ip", $SourceIp,
                "--src-port", "$blockedSourcePort",
                "--dst-ip", $TargetIp,
                "--dst-port", "4660",
                "--protocol", "17"
            )
        )
    )
    if ($aclWrite.ExitCode -ne 0) {
        throw ("{0}: acl-write failed with exit code {1}" -f $probeTag, $aclWrite.ExitCode)
    }

    $seqArgs = New-SeqArgs
    $aclStatusBefore = Invoke-ControlCommand -Label ("{0}_STATUS_BEFORE" -f $probeTag) -Arguments (
        New-ControlArguments -Command "acl-status" -SessionBindingArgs $sessionBindingArgs -CommandArgs $seqArgs
    )
    if ($aclStatusBefore.ExitCode -ne 0) {
        throw ("{0}: acl-status before failed with exit code {1}" -f $probeTag, $aclStatusBefore.ExitCode)
    }
    $beforeCount = [uint32](Get-ControlValue -Output $aclStatusBefore.Output -Key "acl_drop_count")

    Write-Host ("==== {0}_SEND ====" -f $probeTag)
    $replyObserved = Send-TestUdpPacket -LocalPort $blockedSourcePort -RemotePort 4660
    Write-Host ("acl_live_reply_observed={0}" -f $replyObserved)

    $afterCount = $beforeCount
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        Start-Sleep -Milliseconds 250
        $seqArgs = New-SeqArgs
        $aclStatusAfter = Invoke-ControlCommand -Label ("{0}_STATUS_AFTER_{1}" -f $probeTag, $attempt) -Arguments (
            New-ControlArguments -Command "acl-status" -SessionBindingArgs $sessionBindingArgs -CommandArgs $seqArgs
        )
        if ($aclStatusAfter.ExitCode -ne 0) {
            throw ("{0}: acl-status after failed with exit code {1}" -f $probeTag, $aclStatusAfter.ExitCode)
        }
        $afterCount = [uint32](Get-ControlValue -Output $aclStatusAfter.Output -Key "acl_drop_count")
        if ($afterCount -gt $beforeCount) {
            break
        }
    }

    $seqArgs = New-SeqArgs
    $aclClearAfter = Invoke-ControlCommand -Label ("{0}_CLEAR_AFTER" -f $probeTag) -Arguments (
        New-ControlArguments -Command "acl-clear" -SessionBindingArgs $sessionBindingArgs -CommandArgs $seqArgs
    )
    if ($aclClearAfter.ExitCode -ne 0) {
        throw ("{0}: acl-clear after failed with exit code {1}" -f $probeTag, $aclClearAfter.ExitCode)
    }

    $delta = [int]($afterCount - $beforeCount)
    if ($delta -ne 1) {
        throw ("{0}: expected acl_drop_count delta 1, observed {1}" -f $probeTag, $delta)
    }

    return [PSCustomObject]@{
        before = $beforeCount
        after = $afterCount
        delta = $delta
        live_reply_observed = [bool]$replyObserved
    }
}

function Invoke-ReplayMicroProbe {
    param(
        [Parameter(Mandatory)]
        [int]$CycleNumber,

        [Parameter(Mandatory)]
        [pscustomobject]$StatusBefore
    )

    $probeTag = "CYCLE_{0:000}_REPLAY" -f $CycleNumber

    $validSeqArgs = New-SeqArgs
    $probeSeqId = $script:ControlSeqId
    $validStatus = Invoke-ControlCommand -Label ("{0}_VALID" -f $probeTag) -Arguments (
        New-ControlArguments -Command "status" -SessionBindingArgs $sessionBindingArgs -CommandArgs $validSeqArgs
    )
    if ($validStatus.ExitCode -ne 0) {
        throw ("{0}: valid status failed with exit code {1}" -f $probeTag, $validStatus.ExitCode)
    }

    $replayStatus = Invoke-ControlCommand -Label ("{0}_REPEAT" -f $probeTag) -Arguments (
        New-ControlArguments -PreCommandArgs @("--expect-status", "6") -Command "status" -SessionBindingArgs $sessionBindingArgs -CommandArgs @(
            "--seq-id", "$probeSeqId"
        )
    )
    if ($replayStatus.ExitCode -ne 0) {
        throw ("{0}: replay status failed with exit code {1}" -f $probeTag, $replayStatus.ExitCode)
    }
    $statusCode = Get-ControlValue -Output $replayStatus.Output -Key "status_code"
    if ($statusCode -ne "6") {
        throw ("{0}: expected replay status_code=6, got {1}" -f $probeTag, $statusCode)
    }

    $seqArgs = New-SeqArgs
    $statusAfter = Invoke-ControlCommand -Label ("{0}_STATUS_AFTER" -f $probeTag) -Arguments (
        New-ControlArguments -Command "status" -SessionBindingArgs $sessionBindingArgs -CommandArgs $seqArgs
    )
    if ($statusAfter.ExitCode -ne 0) {
        throw ("{0}: post-replay status failed with exit code {1}" -f $probeTag, $statusAfter.ExitCode)
    }
    $snapshotAfter = Get-StatusSnapshot -Output $statusAfter.Output
    $delta = [int]($snapshotAfter.drop_replay - $StatusBefore.drop_replay)
    if ($delta -ne 1) {
        throw ("{0}: expected drop_replay delta 1, observed {1}" -f $probeTag, $delta)
    }
    if ($snapshotAfter.locked -ne 0) {
        throw ("{0}: replay micro-probe unexpectedly locked the session" -f $probeTag)
    }
    if (($snapshotAfter.authorized_mask -band 0x3) -ne 0x3) {
        throw ("{0}: replay micro-probe unexpectedly removed AES/SM4 authorization" -f $probeTag)
    }
    if ($snapshotAfter.lock_events -ne $StatusBefore.lock_events) {
        throw ("{0}: replay micro-probe unexpectedly increased lock_events ({1} -> {2})" -f $probeTag, $StatusBefore.lock_events, $snapshotAfter.lock_events)
    }

    return [PSCustomObject]@{
        status_after = $snapshotAfter
        delta = $delta
        status_code = [int]$statusCode
    }
}

function Publish-SoakArtifacts {
    param(
        [Parameter(Mandatory)]
        [string]$Result,

        [string]$FailureText
    )

    try {
        $reportObject = [ordered]@{}
        $reportObject["mode"] = $(if ($ColdStart) { "sd cold-start soak" } else { "mixed soak" })
        $reportObject["result"] = $Result
        $reportObject["failure_reason"] = $FailureText
        $reportObject["assume_running"] = [bool]$AssumeRunning
        $reportObject["cold_start"] = [bool]$ColdStart
        $reportObject["boot_evidence_found"] = [bool]$script:BootEvidenceFound
        $reportObject["boot_evidence_mode"] = $script:BootEvidenceMode
        $reportObject["boot_evidence_lines"] = @($script:BootEvidenceLines | ForEach-Object { $_ })
        $reportObject["deploy_used"] = [bool]$Deploy
        $reportObject["target_ip"] = $TargetIp
        $reportObject["source_ip"] = $SourceIp
        $reportObject["control_port"] = 4662
        $reportObject["duration_minutes_requested"] = $DurationMinutes
        $reportObject["cycle_interval_seconds"] = $CycleIntervalSeconds
        $reportObject["start_time"] = $startTime.ToString("o")
        $reportObject["end_time"] = $endTime.ToString("o")
        $reportObject["first_control_success_utc"] = $script:FirstControlSuccessUtc
        $reportObject["first_data_success_utc"] = $script:FirstDataSuccessUtc
        $reportObject["session_id"] = $sessionId
        $reportObject["binding_id"] = $bindingId
        $reportObject["uart_log_path"] = $uartLogPath
        $reportObject["report_dir"] = $reportDir
        $reportObject["cycles_completed"] = $cycleResults.Count
        $reportObject["aes_probe_count"] = $aesProbeCount
        $reportObject["sm4_probe_count"] = $sm4ProbeCount
        $reportObject["acl_probe_count"] = $aclProbeCount
        $reportObject["replay_probe_count"] = $replayProbeCount
        $reportObject["hard_bad_uart_evidence"] = @($badUartEvidence | ForEach-Object { $_ })
        $reportObject["soft_uart_warnings"] = @($softUartWarnings | ForEach-Object { $_ })
        $reportObject["baseline_status"] = $baselineStatus
        $reportObject["final_status"] = $currentStatus
        $reportObject["cycles"] = @($cycleResults | ForEach-Object { $_ })

        Set-Content -Path $reportJsonPath -Value ($reportObject | ConvertTo-Json -Depth 8) -Encoding ASCII

        $summaryLines = New-Object System.Collections.Generic.List[string]
        [void]$summaryLines.Add("# Shadow Mirror Soak Summary")
        [void]$summaryLines.Add("")
        [void]$summaryLines.Add("- Result: ``$Result``")
        [void]$summaryLines.Add("- Mode: ``$(if ($ColdStart) { "sd cold-start soak" } else { "mixed soak" })``")
        [void]$summaryLines.Add("- AssumeRunning: ``$AssumeRunning``")
        [void]$summaryLines.Add("- ColdStart: ``$ColdStart``")
        [void]$summaryLines.Add("- Boot evidence found: ``$($script:BootEvidenceFound)``")
        [void]$summaryLines.Add("- Boot evidence mode: ``$($script:BootEvidenceMode)``")
        [void]$summaryLines.Add("- Target IP: ``$TargetIp``")
        [void]$summaryLines.Add("- Source IP: ``$SourceIp``")
        [void]$summaryLines.Add("- Session ID: ``$sessionId``")
        [void]$summaryLines.Add("- Binding ID: ``$bindingId``")
        [void]$summaryLines.Add("- Duration requested: ``$DurationMinutes`` minute(s)")
        [void]$summaryLines.Add("- Cycle interval: ``$CycleIntervalSeconds`` second(s)")
        [void]$summaryLines.Add("- Cycles completed: ``$($cycleResults.Count)``")
        [void]$summaryLines.Add("- AES probes: ``$aesProbeCount``")
        [void]$summaryLines.Add("- SM4 probes: ``$sm4ProbeCount``")
        [void]$summaryLines.Add("- ACL probes: ``$aclProbeCount``")
        [void]$summaryLines.Add("- Replay probes: ``$replayProbeCount``")
        [void]$summaryLines.Add("- UART log: ``$uartLogPath``")
        [void]$summaryLines.Add("- JSON report: ``$reportJsonPath``")
        [void]$summaryLines.Add("- First control success UTC: ``$script:FirstControlSuccessUtc``")
        [void]$summaryLines.Add("- First data success UTC: ``$script:FirstDataSuccessUtc``")

        if ($script:BootEvidenceLines.Count -gt 0) {
            [void]$summaryLines.Add("- Boot evidence lines: ``$($script:BootEvidenceLines -join "; ")``")
        }

        if ($FailureText) {
            [void]$summaryLines.Add("")
            [void]$summaryLines.Add("## Failure")
            [void]$summaryLines.Add("")
            [void]$summaryLines.Add("- Reason: ``$FailureText``")
        }

        if ($badUartEvidence.Count -gt 0) {
            [void]$summaryLines.Add("")
            [void]$summaryLines.Add("## UART Hard Failures")
            [void]$summaryLines.Add("")
            foreach ($entry in $badUartEvidence) {
                [void]$summaryLines.Add("- ``$entry``")
            }
        }

        if ($softUartWarnings.Count -gt 0) {
            [void]$summaryLines.Add("")
            [void]$summaryLines.Add("## UART Warnings")
            [void]$summaryLines.Add("")
            foreach ($entry in $softUartWarnings) {
                [void]$summaryLines.Add("- ``$entry``")
            }
        }

        [void]$summaryLines.Add("")
        [void]$summaryLines.Add("## Cycle Summary")
        [void]$summaryLines.Add("")
        [void]$summaryLines.Add("| Cycle | AES | SM4 | ACL Delta | Replay Delta | locked | authorized_mask | drop_replay | bind_fail | crypto_timeout | crypto_fail |")
        [void]$summaryLines.Add("|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        foreach ($cycle in $cycleResults) {
            $aclDeltaText = if ($null -eq $cycle.acl_delta) { "-" } else { [string]$cycle.acl_delta }
            $replayDeltaText = if ($null -eq $cycle.replay_delta) { "-" } else { [string]$cycle.replay_delta }
            [void]$summaryLines.Add((
                "| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} |" -f
                $cycle.cycle,
                $cycle.aes_result,
                $cycle.sm4_result,
                $aclDeltaText,
                $replayDeltaText,
                $cycle.locked,
                $cycle.authorized_mask,
                $cycle.drop_replay,
                $cycle.bind_fail,
                $cycle.crypto_timeout,
                $cycle.crypto_fail
            ))
        }

        Set-Content -Path $reportMarkdownPath -Value @($summaryLines) -Encoding ASCII
    }
    catch {
        Write-Host ("PUBLISH_SOAK_ARTIFACTS_ERROR={0}" -f $_.Exception.Message)
        Write-Host ("PUBLISH_SOAK_ARTIFACTS_ERROR_TYPE={0}" -f $_.Exception.GetType().FullName)
        throw
    }
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

    if ($ColdStart) {
        $bootCaptureProc = Start-UartCaptureProcess -TimeoutSeconds $bootCaptureTimeoutSeconds -OutputPath $bootUartLogPath -StdoutPath $bootCaptureStdout -StderrPath $bootCaptureStderr
        Write-Host ("Cold-start UART capture started. Boot log path: {0}" -f $bootUartLogPath)
        Confirm-ColdStartBootEvidence
        $captureProc = Start-UartCaptureProcess -TimeoutSeconds $captureTimeoutSeconds -OutputPath $uartLogPath -StdoutPath $captureStdout -StderrPath $captureStderr
        Write-Host ("UART soak capture started. Log path: {0}" -f $uartLogPath)
    }
    else {
        $captureProc = Start-UartCaptureProcess -TimeoutSeconds $captureTimeoutSeconds -OutputPath $uartLogPath -StdoutPath $captureStdout -StderrPath $captureStderr
        Write-Host ("UART capture started. Log path: {0}" -f $uartLogPath)
    }

    if ($AssumeRunning) {
        Write-Host "Assuming board is already running; skipping power-cycle prompt and boot wait."
    }
    elseif (-not $ColdStart) {
        Write-Host "Power-cycle the board now: turn power off for 3 seconds, then power it back on."
        Write-Host ("Waiting {0} seconds before sending soak control traffic..." -f $BootLeadSeconds)
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
    if (-not $script:FirstControlSuccessUtc) {
        $script:FirstControlSuccessUtc = (Get-Date).ToUniversalTime().ToString("o")
    }

    $sessionId = Get-ControlValue -Output $hello.Output -Key "session_id"
    $bindingId = Get-ControlValue -Output $hello.Output -Key "binding_id"
    $sessionBindingArgs = @(
        "--session-id", $sessionId,
        "--binding-id", $bindingId
    )

    $seqArgs = New-SeqArgs
    $setKey = Invoke-ControlCommand -Label "SET_KEY" -Arguments (
        New-ControlArguments -Command "set-key" -SessionBindingArgs $sessionBindingArgs -CommandArgs (
            $seqArgs +
            @(
                "--algo", "aes",
                "--dual-enable"
            )
        )
    )
    if ($setKey.ExitCode -ne 0) {
        throw "set-key failed with exit code $($setKey.ExitCode)"
    }

    $seqArgs = New-SeqArgs
    $statusBaselineResult = Invoke-ControlCommand -Label "STATUS_BASELINE" -Arguments (
        New-ControlArguments -Command "status" -SessionBindingArgs $sessionBindingArgs -CommandArgs $seqArgs
    )
    if ($statusBaselineResult.ExitCode -ne 0) {
        throw "status baseline failed with exit code $($statusBaselineResult.ExitCode)"
    }
    $baselineStatus = Get-StatusSnapshot -Output $statusBaselineResult.Output
    Assert-HealthyStatus -Current $baselineStatus -Previous $baselineStatus -Context "STATUS_BASELINE"
    $currentStatus = $baselineStatus

    $cycleNumber = 0
    while ((Get-Date) -lt $deadline) {
        $cycleNumber += 1
        $cycleStart = Get-Date

        Test-UartHardFailures -Context ("cycle {0} pre-check" -f $cycleNumber)

        $seqArgs = New-SeqArgs
        $statusResult = Invoke-ControlCommand -Label ("STATUS_CYCLE_{0:000}" -f $cycleNumber) -Arguments (
            New-ControlArguments -Command "status" -SessionBindingArgs $sessionBindingArgs -CommandArgs $seqArgs
        )
        if ($statusResult.ExitCode -ne 0) {
            throw ("cycle {0}: status failed with exit code {1}" -f $cycleNumber, $statusResult.ExitCode)
        }
        $statusSnapshot = Get-StatusSnapshot -Output $statusResult.Output
        Assert-HealthyStatus -Current $statusSnapshot -Previous $currentStatus -Context ("cycle {0}" -f $cycleNumber)

        $null = Invoke-DataProbe -Label ("AES_CYCLE_{0:000}" -f $cycleNumber) -Algo "aes" -PayloadHex $aesPayloadHex
        $aesProbeCount += 1
        $null = Invoke-DataProbe -Label ("SM4_CYCLE_{0:000}" -f $cycleNumber) -Algo "sm4" -PayloadHex $sm4PayloadHex
        $sm4ProbeCount += 1

        $aclProbe = $null
        if (($cycleNumber % 10) -eq 0) {
            $aclProbe = Invoke-AclMicroProbe -CycleNumber $cycleNumber
            $aclProbeCount += 1
        }

        $replayProbe = $null
        if (($cycleNumber % 20) -eq 0) {
            $replayProbe = Invoke-ReplayMicroProbe -CycleNumber $cycleNumber -StatusBefore $statusSnapshot
            $replayProbeCount += 1
            $statusSnapshot = $replayProbe.status_after
            Assert-HealthyStatus -Current $statusSnapshot -Previous $currentStatus -Context ("cycle {0} post-replay" -f $cycleNumber)
        }

        Test-UartHardFailures -Context ("cycle {0} post-check" -f $cycleNumber)

        $currentStatus = $statusSnapshot
        $cycleResults.Add([PSCustomObject]@{
            cycle = $cycleNumber
            timestamp = (Get-Date).ToString("o")
            aes_result = "PASS"
            sm4_result = "PASS"
            acl_delta = $(if ($null -eq $aclProbe) { $null } else { $aclProbe.delta })
            replay_delta = $(if ($null -eq $replayProbe) { $null } else { $replayProbe.delta })
            locked = $currentStatus.locked
            authorized_mask = $currentStatus.authorized_mask
            drop_replay = $currentStatus.drop_replay
            bind_fail = $currentStatus.bind_fail
            crypto_timeout = $currentStatus.crypto_timeout
            crypto_fail = $currentStatus.crypto_fail
        }) | Out-Null

        $cycleElapsedSeconds = ((Get-Date) - $cycleStart).TotalSeconds
        $sleepSeconds = [Math]::Floor($CycleIntervalSeconds - $cycleElapsedSeconds)
        if (($sleepSeconds -gt 0) -and ((Get-Date) -lt $deadline)) {
            Start-Sleep -Seconds $sleepSeconds
        }
    }

    Finalize-ColdStartEvidence

    $resultStatus = "PASS"
}
catch {
    $failureReason = $_.Exception.Message
    $resultStatus = "FAIL"
    Write-Host ("SOAK_FAILURE_REASON={0}" -f $failureReason)
}
finally {
    $endTime = Get-Date

    if ($captureProc -and -not $captureProc.HasExited) {
        Stop-Process -Id $captureProc.Id -Force -ErrorAction SilentlyContinue
    }
    if ($captureProc) {
        Wait-Process -Id $captureProc.Id -ErrorAction SilentlyContinue
    }
    if ($bootCaptureProc -and -not $bootCaptureProc.HasExited) {
        Stop-Process -Id $bootCaptureProc.Id -Force -ErrorAction SilentlyContinue
    }
    if ($bootCaptureProc) {
        Wait-Process -Id $bootCaptureProc.Id -ErrorAction SilentlyContinue
    }

    $captureOutput += Get-CaptureOutputLines -StdoutPath $captureStdout -StderrPath $captureStderr

    if ($captureOutput.Count -gt 0) {
        Write-Host "==== CAPTURE SCRIPT OUTPUT ===="
        $captureOutput | ForEach-Object { Write-Host $_ }
    }

    $coldStartUartText = ""
    if (Test-Path $bootUartLogPath) {
        $coldStartUartText = Get-UartText -Path $bootUartLogPath
    }
    if (Test-Path $uartLogPath) {
        $uartText = Get-Content $uartLogPath -Raw
    }
    else {
        $warningText = "UART log file was not created: $uartLogPath"
        [void]$softUartWarnings.Add($warningText)
        Write-Warning $warningText
    }
    if ($coldStartUartText) {
        if ($uartText) {
            $uartText = $coldStartUartText + [Environment]::NewLine + $uartText
        }
        else {
            $uartText = $coldStartUartText
        }
    }

    if ($uartText) {
        $supplementalPassLines = @(
            "LIVE_CTRL PASS",
            "LIVE_AES PASS",
            "LIVE_SM4 PASS",
            "SHADOW_AES PASS",
            "SHADOW_SM4 PASS",
            "SHADOW_FASTPATH PASS"
        )
        $missingPassLines = @(
            $supplementalPassLines | Where-Object { $uartText.IndexOf($_, [System.StringComparison]::Ordinal) -lt 0 }
        )
        if ($missingPassLines.Count -ne 0) {
            $warningText = "UART log is missing supplemental soak evidence lines: {0}" -f ($missingPassLines -join ", ")
            [void]$softUartWarnings.Add($warningText)
            Write-Warning $warningText
        }

        Write-Host "==== UART KEY LINES ===="
        $uartText |
            Select-String "LIVE_CTRL PASS|LIVE_AES PASS|LIVE_SM4 PASS|SHADOW_AES PASS|SHADOW_SM4 PASS|SHADOW_FASTPATH PASS|SHADOW_FASTPATH FALLBACK|shadow compare fail|HALTED|poll timeout" |
            ForEach-Object { Write-Host $_.Line }
    }

    if ($uartText) {
        try {
            Test-UartHardFailures -Context "final-check"
        }
        catch {
            if (-not $failureReason) {
                $failureReason = $_.Exception.Message
            }
            $resultStatus = "FAIL"
        }
    }

    Publish-SoakArtifacts -Result $resultStatus -FailureText $failureReason

    Write-Host "==== SOAK SUMMARY ===="
    if ($resultStatus -eq "PASS") {
        Write-Host "SOAK_RESULT=PASS"
    }
    else {
        Write-Host "SOAK_RESULT=FAIL"
    }
    Write-Host ("SOAK_REPORT_JSON={0}" -f $reportJsonPath)
    Write-Host ("SOAK_REPORT_MD={0}" -f $reportMarkdownPath)
    Write-Host ("UART_LOG={0}" -f $uartLogPath)
    Write-Host ("COLD_START={0}" -f $ColdStart)
    Write-Host ("BOOT_EVIDENCE_FOUND={0}" -f $script:BootEvidenceFound)

    Remove-Item $captureStdout, $captureStderr, $bootCaptureStdout, $bootCaptureStderr -ErrorAction SilentlyContinue
}

if ($resultStatus -ne "PASS") {
    throw $failureReason
}

Write-Host "soak board check completed"
