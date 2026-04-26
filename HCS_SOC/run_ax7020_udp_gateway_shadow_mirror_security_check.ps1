[CmdletBinding()]
param(
    [string]$Port = "COM9",

    [ValidateSet(115200, 230400)]
    [int]$Baud = 115200,

    [switch]$LockBaud,

    [int]$CaptureSeconds = 120,

    [int]$BootLeadSeconds = 20,

    [string]$TargetIp = "192.168.1.20",

    [string]$SourceIp = "192.168.1.11",

    [string]$SdDrive,

    [switch]$Deploy,

    [switch]$AssumeRunning
)

$ErrorActionPreference = "Stop"

# run_ax7020_udp_gateway_shadow_mirror_security_check.ps1
$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $workspace
$captureScript = Join-Path $workspace "capture_uart_boot_log.ps1"
$deployScript = Join-Path $workspace "deploy_ax7020_udp_gateway_shadow_mirror_to_sd.ps1"
$controlScript = Join-Path $workspace "udp_crypto_control.py"
$releaseBootBin = Join-Path $workspace "sd_boot\ax7020_udp_gateway_shadow_mirror\BOOT.BIN"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$uartLogPath = Join-Path $repoRoot ("board_uart_boot_{0}_{1}.txt" -f $Baud, $stamp)
$securityReportDir = Join-Path $repoRoot "doc\reports\board_security"
$securityJsonPath = Join-Path $securityReportDir ("shadow_mirror_security_{0}.json" -f $stamp)
$captureStdout = Join-Path $env:TEMP ("shadow_security_capture_stdout_{0}.txt" -f $stamp)
$captureStderr = Join-Path $env:TEMP ("shadow_security_capture_stderr_{0}.txt" -f $stamp)
$script:ControlSeqId = 0
$pythonExe = (Get-Command python.exe -ErrorAction Stop).Source
$lockedDataPort = 54220
$unlockedDataPort = 54221
$reauthDataPort = 54222
$timeoutDataPort = 54223
$sessionTimeoutIdleSeconds = 11
$dataPayload = [byte[]](0..15)

if (-not (Test-Path $releaseBootBin)) {
    throw "Release BOOT.BIN not found: $releaseBootBin"
}
if (-not (Test-Path $controlScript)) {
    throw "Control helper not found: $controlScript"
}

$expectedHash = (Get-FileHash $releaseBootBin -Algorithm SHA256).Hash.ToUpperInvariant()
New-Item -ItemType Directory -Force -Path $securityReportDir | Out-Null

function Normalize-PathEnvironment {
    $processEnv = [System.Environment]::GetEnvironmentVariables('Process')
    if ($processEnv.Contains('Path') -and $processEnv.Contains('PATH')) {
        [System.Environment]::SetEnvironmentVariable('PATH', $null, 'Process')
    }
}

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
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $proc = Start-Process -FilePath $pythonExe `
            -ArgumentList (@($controlScript) + $Arguments) `
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
            ElapsedMs = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
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
    return @("--seq-id", "$script:ControlSeqId")
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

function Send-TestUdpPacket {
    param(
        [Parameter(Mandatory)]
        [int]$LocalPort,

        [Parameter(Mandatory)]
        [int]$RemotePort
    )

    $client = [System.Net.Sockets.UdpClient]::new(([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($SourceIp), $LocalPort)))
    $client.Client.ReceiveTimeout = 750
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        [void]$client.Send($dataPayload, $dataPayload.Length, $TargetIp, $RemotePort)
        $remoteEndpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        try {
            [void]$client.Receive([ref]$remoteEndpoint)
            return [PSCustomObject]@{
                ReplyReceived = $true
                ElapsedMs = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
            }
        }
        catch [System.Net.Sockets.SocketException] {
            return [PSCustomObject]@{
                ReplyReceived = $false
                ElapsedMs = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
            }
        }
    }
    finally {
        $client.Dispose()
    }
}

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
if ($LockBaud) {
    $captureArgs += "-LockBaud"
}

Normalize-PathEnvironment
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
    Write-Host ("Waiting {0} seconds before sending security control traffic..." -f $BootLeadSeconds)
    Start-Sleep -Seconds $BootLeadSeconds
}

$globalArgs = @(
    "--ip", $TargetIp,
    "--source-ip", $SourceIp
)
$replayThresholdLockReason = 3
$unauthorizedDropReason = 2

$hello = Invoke-ControlCommandWithRetry -Label "HELLO" -Arguments (
    $globalArgs +
    @("hello")
) -RetryCount 10 -RetryDelaySeconds 1
if ($hello.ExitCode -ne 0) {
    throw "hello failed with exit code $($hello.ExitCode)"
}

$sessionId = (Get-ControlValue -Output $hello.Output -Key "session_id")
$bindingId = (Get-ControlValue -Output $hello.Output -Key "binding_id")
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

$baselineStatusSeq = $script:ControlSeqId + 1
$seqArgs = New-SeqArgs
$statusBaseline = Invoke-ControlCommand -Label "STATUS_BASELINE" -Arguments (
    $globalArgs +
    @("status") +
    $sessionBindingArgs +
    $seqArgs
)
if ($statusBaseline.ExitCode -ne 0) {
    throw "status baseline failed with exit code $($statusBaseline.ExitCode)"
}

$dropReplayBaseline = [uint32](Get-ControlValue -Output $statusBaseline.Output -Key "drop_replay")
$dropUnauthorizedBaseline = [uint32](Get-ControlValue -Output $statusBaseline.Output -Key "drop_unauthorized")
$lockEventsBaseline = [uint32](Get-ControlValue -Output $statusBaseline.Output -Key "lock_events")
$lockedBaseline = [uint32](Get-ControlValue -Output $statusBaseline.Output -Key "locked")
$authorizedBaseline = [uint32](Get-ControlValue -Output $statusBaseline.Output -Key "authorized_mask")
if ($lockedBaseline -ne 0) {
    throw "Expected unlocked baseline session"
}
if (($authorizedBaseline -band 0x3) -ne 0x3) {
    throw "Expected baseline authorized_mask to include AES and SM4"
}

$replayLockSw = [System.Diagnostics.Stopwatch]::StartNew()
$replay1 = Invoke-ControlCommand -Label "SECURITY_REPLAY_1" -Arguments (
    $globalArgs +
    @("--expect-status", "6") +
    @("status") +
    $sessionBindingArgs +
    @("--seq-id", "$baselineStatusSeq")
)
$replay2 = Invoke-ControlCommand -Label "SECURITY_REPLAY_2" -Arguments (
    $globalArgs +
    @("--expect-status", "6") +
    @("status") +
    $sessionBindingArgs +
    @("--seq-id", "$baselineStatusSeq")
)
$replay3 = Invoke-ControlCommand -Label "SECURITY_REPLAY_3" -Arguments (
    $globalArgs +
    @("--expect-status", "6") +
    @("status") +
    $sessionBindingArgs +
    @("--seq-id", "$baselineStatusSeq")
)
foreach ($replayResult in @($replay1, $replay2, $replay3)) {
    if ($replayResult.ExitCode -ne 0) {
        throw "$($replayResult.Label) failed with exit code $($replayResult.ExitCode)"
    }
    if ((Get-ControlValue -Output $replayResult.Output -Key "status_code") -ne "6") {
        throw "$($replayResult.Label) did not report replay status"
    }
}

$seqArgs = New-SeqArgs
$statusLocked = Invoke-ControlCommand -Label "STATUS_LOCKED" -Arguments (
    $globalArgs +
    @("status") +
    $sessionBindingArgs +
    $seqArgs
)
if ($statusLocked.ExitCode -ne 0) {
    throw "status locked failed with exit code $($statusLocked.ExitCode)"
}

$lockedAfterReplay = [uint32](Get-ControlValue -Output $statusLocked.Output -Key "locked")
$authorizedAfterReplay = [uint32](Get-ControlValue -Output $statusLocked.Output -Key "authorized_mask")
$dropReplayAfter = [uint32](Get-ControlValue -Output $statusLocked.Output -Key "drop_replay")
$lockEventsAfter = [uint32](Get-ControlValue -Output $statusLocked.Output -Key "lock_events")
$lastLockReasonAfterReplay = [uint32](Get-ControlValue -Output $statusLocked.Output -Key "last_lock_reason")
$replaySeenAfterReplay = [uint32](Get-ControlValue -Output $statusLocked.Output -Key "replay_seen")
if ($lockedAfterReplay -ne 1) {
    throw "Expected session to auto-lock after replay threshold"
}
if ($authorizedAfterReplay -ne 0) {
    throw "Expected authorized_mask to be cleared after auto-lock"
}
if (($dropReplayAfter - $dropReplayBaseline) -lt 3) {
    throw "Expected at least three replay drops"
}
if (($lockEventsAfter - $lockEventsBaseline) -lt 1) {
    throw "Expected lock_events to increase after replay threshold"
}
if ($lastLockReasonAfterReplay -ne $replayThresholdLockReason) {
    throw "Expected last_lock_reason to report replay-threshold lock"
}
if ($replaySeenAfterReplay -ne 1) {
    throw "Expected replay_seen to latch after replay detection"
}
$replayLockSw.Stop()

$seqArgs = New-SeqArgs
$setKeyLocked = Invoke-ControlCommand -Label "SET_KEY_LOCKED" -Arguments (
    $globalArgs +
    @("--expect-status", "7") +
    @("set-key") +
    $sessionBindingArgs +
    $seqArgs +
    @(
        "--algo", "aes",
        "--dual-enable"
    )
)
if ($setKeyLocked.ExitCode -ne 0) {
    throw "set-key while locked failed with exit code $($setKeyLocked.ExitCode)"
}
if ((Get-ControlValue -Output $setKeyLocked.Output -Key "status_code") -ne "7") {
    throw "Expected SET_KEY_LOCKED to return LOCKED status"
}

Write-Host "==== DATA_BEFORE_REAUTH ===="
$replyWhileLockedResult = Send-TestUdpPacket -LocalPort $lockedDataPort -RemotePort 4660
$replyWhileLocked = [bool]$replyWhileLockedResult.ReplyReceived
Write-Host ("reply_received={0}" -f $replyWhileLocked)
Write-Host ("elapsed_ms={0}" -f $replyWhileLockedResult.ElapsedMs)
if ($replyWhileLocked) {
    throw "Locked session unexpectedly received data-plane reply"
}

$seqArgs = New-SeqArgs
$statusAfterLockedData = Invoke-ControlCommand -Label "STATUS_AFTER_LOCKED_DATA" -Arguments (
    $globalArgs +
    @("status") +
    $sessionBindingArgs +
    $seqArgs
)
if ($statusAfterLockedData.ExitCode -ne 0) {
    throw "status after locked data failed with exit code $($statusAfterLockedData.ExitCode)"
}
$dropUnauthorizedAfterLockedData = [uint32](Get-ControlValue -Output $statusAfterLockedData.Output -Key "drop_unauthorized")
$lastDropReasonAfterLockedData = [uint32](Get-ControlValue -Output $statusAfterLockedData.Output -Key "last_drop_reason")
if (($dropUnauthorizedAfterLockedData - $dropUnauthorizedBaseline) -lt 1) {
    throw "Expected unauthorized drop counter to increase while locked"
}
if ($lastDropReasonAfterLockedData -ne $unauthorizedDropReason) {
    throw "Expected last_drop_reason to report unauthorized drop while locked"
}

$seqArgs = New-SeqArgs
$unlockSw = [System.Diagnostics.Stopwatch]::StartNew()
$unlock = Invoke-ControlCommand -Label "UNLOCK" -Arguments (
    $globalArgs +
    @("unlock") +
    $sessionBindingArgs +
    $seqArgs
)
if ($unlock.ExitCode -ne 0) {
    throw "unlock failed with exit code $($unlock.ExitCode)"
}

$seqArgs = New-SeqArgs
$statusAfterUnlock = Invoke-ControlCommand -Label "STATUS_AFTER_UNLOCK" -Arguments (
    $globalArgs +
    @("status") +
    $sessionBindingArgs +
    $seqArgs
)
if ($statusAfterUnlock.ExitCode -ne 0) {
    throw "status after unlock failed with exit code $($statusAfterUnlock.ExitCode)"
}

$lockedAfterUnlock = [uint32](Get-ControlValue -Output $statusAfterUnlock.Output -Key "locked")
$authorizedAfterUnlock = [uint32](Get-ControlValue -Output $statusAfterUnlock.Output -Key "authorized_mask")
if ($lockedAfterUnlock -ne 0) {
    throw "Expected session to be unlocked"
}
if ($authorizedAfterUnlock -ne 0) {
    throw "Expected authorized_mask to remain zero after unlock before reauthorization"
}
$unlockSw.Stop()

Write-Host "==== DATA_AFTER_UNLOCK ===="
$replyAfterUnlockResult = Send-TestUdpPacket -LocalPort $unlockedDataPort -RemotePort 4660
$replyAfterUnlock = [bool]$replyAfterUnlockResult.ReplyReceived
Write-Host ("reply_received={0}" -f $replyAfterUnlock)
Write-Host ("elapsed_ms={0}" -f $replyAfterUnlockResult.ElapsedMs)
if ($replyAfterUnlock) {
    throw "Unlocked but non-reauthorized session unexpectedly received data-plane reply"
}

$seqArgs = New-SeqArgs
$statusAfterUnlockedData = Invoke-ControlCommand -Label "STATUS_AFTER_UNLOCKED_DATA" -Arguments (
    $globalArgs +
    @("status") +
    $sessionBindingArgs +
    $seqArgs
)
if ($statusAfterUnlockedData.ExitCode -ne 0) {
    throw "status after unlocked data failed with exit code $($statusAfterUnlockedData.ExitCode)"
}
$dropUnauthorizedAfterUnlock = [uint32](Get-ControlValue -Output $statusAfterUnlockedData.Output -Key "drop_unauthorized")
if (($dropUnauthorizedAfterUnlock - $dropUnauthorizedAfterLockedData) -lt 1) {
    throw "Expected unauthorized drop counter to increase again after unlock without reauthorization"
}

$seqArgs = New-SeqArgs
$reauthSw = [System.Diagnostics.Stopwatch]::StartNew()
$setKeyReauth = Invoke-ControlCommand -Label "SET_KEY_REAUTH" -Arguments (
    $globalArgs +
    @("set-key") +
    $sessionBindingArgs +
    $seqArgs +
    @(
        "--algo", "aes",
        "--dual-enable"
    )
)
if ($setKeyReauth.ExitCode -ne 0) {
    throw "set-key reauth failed with exit code $($setKeyReauth.ExitCode)"
}

$seqArgs = New-SeqArgs
$statusAfterReauth = Invoke-ControlCommand -Label "STATUS_AFTER_REAUTH" -Arguments (
    $globalArgs +
    @("status") +
    $sessionBindingArgs +
    $seqArgs
)
if ($statusAfterReauth.ExitCode -ne 0) {
    throw "status after reauth failed with exit code $($statusAfterReauth.ExitCode)"
}
$authorizedAfterReauth = [uint32](Get-ControlValue -Output $statusAfterReauth.Output -Key "authorized_mask")
if (($authorizedAfterReauth -band 0x3) -ne 0x3) {
    throw "Expected authorized_mask to be restored after reauthorization"
}

Write-Host "==== DATA_AFTER_REAUTH ===="
$replyAfterReauthResult = Send-TestUdpPacket -LocalPort $reauthDataPort -RemotePort 4660
$replyAfterReauth = [bool]$replyAfterReauthResult.ReplyReceived
Write-Host ("reply_received={0}" -f $replyAfterReauth)
Write-Host ("elapsed_ms={0}" -f $replyAfterReauthResult.ElapsedMs)
if (-not $replyAfterReauth) {
    throw "Reauthorized session did not receive data-plane reply"
}
$reauthSw.Stop()

$timedOutSessionBindingArgs = @($sessionBindingArgs)

Write-Host "==== SESSION_TIMEOUT_IDLE ===="
Start-Sleep -Seconds $sessionTimeoutIdleSeconds

Write-Host "==== DATA_AFTER_TIMEOUT ===="
$replyAfterTimeoutResult = Send-TestUdpPacket -LocalPort $timeoutDataPort -RemotePort 4660
$replyAfterTimeout = [bool]$replyAfterTimeoutResult.ReplyReceived
Write-Host ("reply_received={0}" -f $replyAfterTimeout)
Write-Host ("elapsed_ms={0}" -f $replyAfterTimeoutResult.ElapsedMs)
if ($replyAfterTimeout) {
    throw "Timed-out session unexpectedly received data-plane reply"
}

$seqArgs = New-SeqArgs
$statusTimeoutOldSession = Invoke-ControlCommand -Label "STATUS_TIMEOUT_OLD_SESSION" -Arguments (
    $globalArgs +
    @("--expect-status", "8") +
    @("status") +
    $timedOutSessionBindingArgs +
    $seqArgs
)
if ($statusTimeoutOldSession.ExitCode -ne 0) {
    throw "status timeout old session failed with exit code $($statusTimeoutOldSession.ExitCode)"
}
if ((Get-ControlValue -Output $statusTimeoutOldSession.Output -Key "status_code") -ne "8") {
    throw "Expected STATUS_TIMEOUT_OLD_SESSION to return NO_SESSION"
}

$timeoutReauthSw = [System.Diagnostics.Stopwatch]::StartNew()
$helloTimeoutReauth = Invoke-ControlCommandWithRetry -Label "HELLO_TIMEOUT_REAUTH" -Arguments (
    $globalArgs +
    @("hello")
) -RetryCount 10 -RetryDelaySeconds 1
if ($helloTimeoutReauth.ExitCode -ne 0) {
    throw "hello timeout reauth failed with exit code $($helloTimeoutReauth.ExitCode)"
}

$timeoutReauthSessionId = (Get-ControlValue -Output $helloTimeoutReauth.Output -Key "session_id")
$timeoutReauthBindingId = (Get-ControlValue -Output $helloTimeoutReauth.Output -Key "binding_id")
$timeoutReauthSessionBindingArgs = @(
    "--session-id", $timeoutReauthSessionId,
    "--binding-id", $timeoutReauthBindingId
)

$seqArgs = New-SeqArgs
$setKeyTimeoutReauth = Invoke-ControlCommand -Label "SET_KEY_TIMEOUT_REAUTH" -Arguments (
    $globalArgs +
    @("set-key") +
    $timeoutReauthSessionBindingArgs +
    $seqArgs +
    @(
        "--algo", "aes",
        "--dual-enable"
    )
)
if ($setKeyTimeoutReauth.ExitCode -ne 0) {
    throw "set-key timeout reauth failed with exit code $($setKeyTimeoutReauth.ExitCode)"
}

$seqArgs = New-SeqArgs
$statusAfterTimeoutReauth = Invoke-ControlCommand -Label "STATUS_AFTER_TIMEOUT_REAUTH" -Arguments (
    $globalArgs +
    @("status") +
    $timeoutReauthSessionBindingArgs +
    $seqArgs
)
if ($statusAfterTimeoutReauth.ExitCode -ne 0) {
    throw "status after timeout reauth failed with exit code $($statusAfterTimeoutReauth.ExitCode)"
}
$timeoutSeenAfterTimeoutReauth = [uint32](Get-ControlValue -Output $statusAfterTimeoutReauth.Output -Key "timeout_seen")
$reauthSeenAfterTimeoutReauth = [uint32](Get-ControlValue -Output $statusAfterTimeoutReauth.Output -Key "reauth_seen")
if ($timeoutSeenAfterTimeoutReauth -ne 0) {
    throw "Expected timeout_seen to clear after timeout reauthorization"
}
if ($reauthSeenAfterTimeoutReauth -ne 1) {
    throw "Expected reauth_seen to latch after timeout reauthorization"
}
$timeoutReauthSw.Stop()

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

$uartText = Get-Content $uartLogPath -Raw
if ($null -eq $uartText) {
    $uartText = ""
}
$requiredPassLines = @(
    "LIVE_CTRL PASS",
    "LIVE_AES PASS"
)
$missingPassLines = @(
    $requiredPassLines | Where-Object { $uartText.IndexOf($_, [System.StringComparison]::Ordinal) -lt 0 }
)

Write-Host "==== UART KEY LINES ===="
if ($uartText.Length -gt 0) {
    $uartText |
        Select-String "LIVE_CTRL PASS|LIVE_AES PASS|drop unauthorized|locked|auth fail|replay|queue full" |
        ForEach-Object { Write-Host $_.Line }
}

if ($missingPassLines.Count -ne 0) {
    Write-Warning ("UART log is missing supplemental security evidence lines: {0}" -f ($missingPassLines -join ", "))
}

Write-Host "==== CONTROL SUMMARY ===="
Write-Host ("session_id={0}" -f $sessionId)
Write-Host ("binding_id={0}" -f $bindingId)
Write-Host ("drop_replay_baseline={0}" -f $dropReplayBaseline)
Write-Host ("drop_replay_after={0}" -f $dropReplayAfter)
Write-Host ("replay_seen_after_replay={0}" -f $replaySeenAfterReplay)
Write-Host ("lock_events_baseline={0}" -f $lockEventsBaseline)
Write-Host ("lock_events_after={0}" -f $lockEventsAfter)
Write-Host ("last_lock_reason_after_replay={0}" -f $lastLockReasonAfterReplay)
Write-Host ("drop_unauthorized_baseline={0}" -f $dropUnauthorizedBaseline)
Write-Host ("drop_unauthorized_after_locked_data={0}" -f $dropUnauthorizedAfterLockedData)
Write-Host ("drop_unauthorized_after_unlock={0}" -f $dropUnauthorizedAfterUnlock)
Write-Host ("timeout_seen_after_timeout_reauth={0}" -f $timeoutSeenAfterTimeoutReauth)
Write-Host ("reauth_seen_after_timeout_reauth={0}" -f $reauthSeenAfterTimeoutReauth)
Write-Host ("last_drop_reason_after_locked_data={0}" -f $lastDropReasonAfterLockedData)
Write-Host ("reply_while_locked={0}" -f $replyWhileLocked)
Write-Host ("reply_after_unlock_before_reauth={0}" -f $replyAfterUnlock)
Write-Host ("reply_after_reauth={0}" -f $replyAfterReauth)
Write-Host ("reply_while_locked_elapsed_ms={0}" -f $replyWhileLockedResult.ElapsedMs)
Write-Host ("reply_after_unlock_elapsed_ms={0}" -f $replyAfterUnlockResult.ElapsedMs)
Write-Host ("reply_after_reauth_elapsed_ms={0}" -f $replyAfterReauthResult.ElapsedMs)
Write-Host ("reply_after_timeout_elapsed_ms={0}" -f $replyAfterTimeoutResult.ElapsedMs)
Write-Host ("replay_lock_window_ms={0}" -f ([Math]::Round($replayLockSw.Elapsed.TotalMilliseconds, 3)))
Write-Host ("unlock_status_window_ms={0}" -f ([Math]::Round($unlockSw.Elapsed.TotalMilliseconds, 3)))
Write-Host ("reauth_resume_window_ms={0}" -f ([Math]::Round($reauthSw.Elapsed.TotalMilliseconds, 3)))
Write-Host ("timeout_reauth_window_ms={0}" -f ([Math]::Round($timeoutReauthSw.Elapsed.TotalMilliseconds, 3)))
$statusBaseline.Output | ForEach-Object { Write-Host $_ }
$statusLocked.Output | ForEach-Object { Write-Host $_ }
$statusAfterLockedData.Output | ForEach-Object { Write-Host $_ }
$statusAfterUnlock.Output | ForEach-Object { Write-Host $_ }
$statusAfterUnlockedData.Output | ForEach-Object { Write-Host $_ }
$statusAfterReauth.Output | ForEach-Object { Write-Host $_ }

$securitySummary = [PSCustomObject]@{
    timestamp = (Get-Date).ToString("s")
    uart_log = $uartLogPath
    target_ip = $TargetIp
    source_ip = $SourceIp
    session_id = $sessionId
    binding_id = $bindingId
    control_metrics = [PSCustomObject]@{
        drop_replay_baseline = $dropReplayBaseline
        drop_replay_after = $dropReplayAfter
        replay_seen_after_replay = $replaySeenAfterReplay
        lock_events_baseline = $lockEventsBaseline
        lock_events_after = $lockEventsAfter
        last_lock_reason_after_replay = $lastLockReasonAfterReplay
        drop_unauthorized_baseline = $dropUnauthorizedBaseline
        drop_unauthorized_after_locked_data = $dropUnauthorizedAfterLockedData
        drop_unauthorized_after_unlock = $dropUnauthorizedAfterUnlock
        timeout_seen_after_timeout_reauth = $timeoutSeenAfterTimeoutReauth
        reauth_seen_after_timeout_reauth = $reauthSeenAfterTimeoutReauth
        last_drop_reason_after_locked_data = $lastDropReasonAfterLockedData
    }
    timing_ms = [PSCustomObject]@{
        hello_ms = $hello.ElapsedMs
        set_key_ms = $setKey.ElapsedMs
        reply_while_locked_elapsed_ms = $replyWhileLockedResult.ElapsedMs
        reply_after_unlock_elapsed_ms = $replyAfterUnlockResult.ElapsedMs
        set_key_reauth_ms = $setKeyReauth.ElapsedMs
        reply_after_reauth_elapsed_ms = $replyAfterReauthResult.ElapsedMs
        reply_after_timeout_elapsed_ms = $replyAfterTimeoutResult.ElapsedMs
        hello_timeout_reauth_ms = $helloTimeoutReauth.ElapsedMs
        set_key_timeout_reauth_ms = $setKeyTimeoutReauth.ElapsedMs
        replay_lock_window_ms = [Math]::Round($replayLockSw.Elapsed.TotalMilliseconds, 3)
        unlock_status_window_ms = [Math]::Round($unlockSw.Elapsed.TotalMilliseconds, 3)
        reauth_resume_window_ms = [Math]::Round($reauthSw.Elapsed.TotalMilliseconds, 3)
        timeout_reauth_window_ms = [Math]::Round($timeoutReauthSw.Elapsed.TotalMilliseconds, 3)
    }
    reply_flags = [PSCustomObject]@{
        reply_while_locked = $replyWhileLocked
        reply_after_unlock_before_reauth = $replyAfterUnlock
        reply_after_reauth = $replyAfterReauth
    }
}
$securitySummary | ConvertTo-Json -Depth 6 | Set-Content -Path $securityJsonPath -Encoding utf8
Write-Host ("security_json={0}" -f $securityJsonPath)

Write-Host "security board check completed"

Remove-Item $captureStdout, $captureStderr -ErrorAction SilentlyContinue
