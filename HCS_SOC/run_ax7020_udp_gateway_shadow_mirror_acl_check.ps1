[CmdletBinding()]
param(
    [string]$Port = "COM9",

    [ValidateSet(115200, 230400)]
    [int]$Baud = 115200,

    [int]$CaptureSeconds = 60,

    [int]$BootLeadSeconds = 20,

    [string]$TargetIp = "192.168.1.20",

    [string]$SourceIp = "192.168.1.11",

    [string]$SdDrive,

    [switch]$Deploy,

    [switch]$AssumeRunning
)

$ErrorActionPreference = "Stop"

# run_ax7020_udp_gateway_shadow_mirror_acl_check.ps1
$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $workspace
$captureScript = Join-Path $workspace "capture_uart_boot_log.ps1"
$deployScript = Join-Path $workspace "deploy_ax7020_udp_gateway_shadow_mirror_to_sd.ps1"
$controlScript = Join-Path $workspace "udp_crypto_control.py"
$releaseBootBin = Join-Path $workspace "sd_boot\ax7020_udp_gateway_shadow_mirror\BOOT.BIN"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$uartLogPath = Join-Path $repoRoot ("board_uart_boot_{0}_{1}.txt" -f $Baud, $stamp)
$captureStdout = Join-Path $env:TEMP ("shadow_acl_capture_stdout_{0}.txt" -f $stamp)
$captureStderr = Join-Path $env:TEMP ("shadow_acl_capture_stderr_{0}.txt" -f $stamp)
$script:ControlSeqId = 0
$blockedSourcePort = 54060

if (-not (Test-Path $releaseBootBin)) {
    throw "Release BOOT.BIN not found: $releaseBootBin"
}
if (-not (Test-Path $controlScript)) {
    throw "Control helper not found: $controlScript"
}

$expectedHash = (Get-FileHash $releaseBootBin -Algorithm SHA256).Hash.ToUpperInvariant()

function New-ControlArguments {
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [string[]]$SessionBindingArgs = @(),

        [string[]]$CommandArgs = @()
    )

    if (-not $script:ControlGlobalArgs -or $script:ControlGlobalArgs.Count -eq 0) {
        throw "Control global arguments were not initialized"
    }

    return @(
        $script:ControlGlobalArgs +
        @($Command) +
        $SessionBindingArgs +
        $CommandArgs
    )
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

function Send-MatchingUdpPacket {
    param(
        [string]$LocalIp,
        [int]$LocalPort,
        [string]$RemoteIp,
        [int]$RemotePort
    )

    $client = [System.Net.Sockets.UdpClient]::new(([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($LocalIp), $LocalPort)))
    $client.Client.ReceiveTimeout = 750
    try {
        $payload = [byte[]](0..15)
        [void]$client.Send($payload, $payload.Length, $RemoteIp, $RemotePort)
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
    Write-Host ("Waiting {0} seconds before sending ACL control traffic..." -f $BootLeadSeconds)
    Start-Sleep -Seconds $BootLeadSeconds
}

$globalArgs = @(
    "--ip", $TargetIp,
    "--source-ip", $SourceIp
)
$script:ControlGlobalArgs = $globalArgs
$aclDropReasonExpected = 4

$hello = Invoke-ControlCommandWithRetry -Label "HELLO" -Arguments (
    $globalArgs +
    @("hello")
) -RetryCount 10 -RetryDelaySeconds 1
if ($hello.ExitCode -ne 0) {
    throw "hello failed with exit code $($hello.ExitCode)"
}

$sessionLine = $hello.Output | Where-Object { $_ -match "^session_id=0x" } | Select-Object -First 1
$bindingLine = $hello.Output | Where-Object { $_ -match "^binding_id=0x" } | Select-Object -First 1
if (-not $sessionLine -or -not $bindingLine) {
    throw "Failed to parse hello response for session_id/binding_id"
}

$sessionId = ($sessionLine -replace "^session_id=", "")
$bindingId = ($bindingLine -replace "^binding_id=", "")

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

$seqArgs = New-SeqArgs
$gatewayStatus = Invoke-ControlCommand -Label "STATUS" -Arguments (
    $globalArgs +
    @("status") +
    $sessionBindingArgs +
    $seqArgs
)
if ($gatewayStatus.ExitCode -ne 0) {
    throw "status failed with exit code $($gatewayStatus.ExitCode)"
}

$seqArgs = New-SeqArgs
$aclClear = Invoke-ControlCommand -Label "ACL_CLEAR" -Arguments (
    $globalArgs +
    @("acl-clear") +
    $sessionBindingArgs +
    $seqArgs
)
if ($aclClear.ExitCode -ne 0) {
    throw "acl-clear failed with exit code $($aclClear.ExitCode)"
}

$seqArgs = New-SeqArgs
$aclWrite = Invoke-ControlCommand -Label "ACL_WRITE" -Arguments (
    $globalArgs +
    @("acl-write") +
    $sessionBindingArgs +
    $seqArgs +
    @(
        "--src-ip", $SourceIp,
        "--src-port", "$blockedSourcePort",
        "--dst-ip", $TargetIp,
        "--dst-port", "4660",
        "--protocol", "17"
    )
)
if ($aclWrite.ExitCode -ne 0) {
    throw "acl-write failed with exit code $($aclWrite.ExitCode)"
}

$seqArgs = New-SeqArgs
$aclStatusBefore = Invoke-ControlCommand -Label "ACL_STATUS_BEFORE" -Arguments (
    $globalArgs +
    @("acl-status") +
    $sessionBindingArgs +
    $seqArgs
)
if ($aclStatusBefore.ExitCode -ne 0) {
    throw "acl-status before failed with exit code $($aclStatusBefore.ExitCode)"
}
$aclDropCountBefore = [uint32](Get-ControlValue -Output $aclStatusBefore.Output -Key "acl_drop_count")

$aclFailureReason = $null
$statusAfterSend = $null
$aclStatusAfter = $null
$statusAfterDrop = $null
$liveReplyObserved = Send-MatchingUdpPacket -LocalIp $SourceIp -LocalPort $blockedSourcePort -RemoteIp $TargetIp -RemotePort 4660

$seqArgs = New-SeqArgs
$statusAfterSend = Invoke-ControlCommand -Label "STATUS_AFTER_SEND" -Arguments (
    $globalArgs +
    @("status") +
    $sessionBindingArgs +
    $seqArgs
)
if ($statusAfterSend.ExitCode -ne 0) {
    $aclFailureReason = "status after send failed with exit code $($statusAfterSend.ExitCode)"
}

$aclDropCountAfter = $aclDropCountBefore
for ($attempt = 1; $attempt -le 10; $attempt++) {
    Start-Sleep -Milliseconds 200
    $seqArgs = New-SeqArgs
    $aclStatusAfter = Invoke-ControlCommand -Label "ACL_STATUS_AFTER" -Arguments (
        $globalArgs +
        @("acl-status") +
        $sessionBindingArgs +
        $seqArgs
    )
    if ($aclStatusAfter.ExitCode -ne 0) {
        if (-not $aclFailureReason) {
            $aclFailureReason = "acl-status after failed with exit code $($aclStatusAfter.ExitCode)"
        }
        break
    }

    $aclDropCountAfter = [uint32](Get-ControlValue -Output $aclStatusAfter.Output -Key "acl_drop_count")
    if ($aclDropCountAfter -gt $aclDropCountBefore) {
        break
    }
}
if (($aclDropCountAfter -le $aclDropCountBefore) -and (-not $aclFailureReason)) {
    $aclFailureReason = "ACL counter did not increase after sending a blocked packet"
}

$lastDropReasonAfterSend = $null
$aclHitSeenAfterSend = $null
if ($statusAfterSend -and $statusAfterSend.ExitCode -eq 0) {
    try {
        $lastDropReasonAfterSend = [uint32](Get-ControlValue -Output $statusAfterSend.Output -Key "last_drop_reason")
        $aclHitSeenAfterSend = [uint32](Get-ControlValue -Output $statusAfterSend.Output -Key "acl_hit_seen")
    }
    catch {
        $lastDropReasonAfterSend = $null
        $aclHitSeenAfterSend = $null
    }
}

if (-not $aclFailureReason) {
    $seqArgs = New-SeqArgs
    $statusAfterDrop = Invoke-ControlCommand -Label "STATUS_AFTER_DROP" -Arguments (
        $globalArgs +
        @("status") +
        $sessionBindingArgs +
        $seqArgs
    )
    if ($statusAfterDrop.ExitCode -ne 0) {
        $aclFailureReason = "status after drop failed with exit code $($statusAfterDrop.ExitCode)"
    }
}

$lastDropReasonAfterDrop = $null
$aclHitSeenAfterDrop = $null
if ($statusAfterDrop -and $statusAfterDrop.ExitCode -eq 0) {
    try {
        $lastDropReasonAfterDrop = [uint32](Get-ControlValue -Output $statusAfterDrop.Output -Key "last_drop_reason")
        $aclHitSeenAfterDrop = [uint32](Get-ControlValue -Output $statusAfterDrop.Output -Key "acl_hit_seen")
    }
    catch {
        $lastDropReasonAfterDrop = $null
        $aclHitSeenAfterDrop = $null
    }
}

if (
    (-not $aclFailureReason) -and
    ($lastDropReasonAfterSend -ne $aclDropReasonExpected) -and
    ($lastDropReasonAfterDrop -ne $aclDropReasonExpected)
) {
    $aclFailureReason = "Expected last_drop_reason to report ACL drop"
}
if (
    (-not $aclFailureReason) -and
    (
        (($lastDropReasonAfterSend -eq $aclDropReasonExpected) -and ($aclHitSeenAfterSend -ne 1)) -or
        (($lastDropReasonAfterDrop -eq $aclDropReasonExpected) -and ($aclHitSeenAfterDrop -ne 1))
    )
) {
    $aclFailureReason = "Expected acl_hit_seen=1 when last_drop_reason reports ACL drop"
}

$seqArgs = New-SeqArgs
$status = Invoke-ControlCommand -Label "ACL_STATUS" -Arguments (
    $globalArgs +
    @("acl-status") +
    $sessionBindingArgs +
    $seqArgs
)
if ($status.ExitCode -ne 0) {
    throw "acl-status failed with exit code $($status.ExitCode)"
}

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
    "LIVE_CTRL PASS"
)
$missingPassLines = @(
    $requiredPassLines | Where-Object { $uartText.IndexOf($_, [System.StringComparison]::Ordinal) -lt 0 }
)

Write-Host "==== UART KEY LINES ===="
if ($uartText.Length -gt 0) {
    $uartText |
        Select-String "LIVE_CTRL PASS|udp_crypto_gateway: rx_callback entry|udp_crypto_gateway: shadow queued|SHADOW_FASTPATH PASS|SHADOW_AES PASS" |
        ForEach-Object { Write-Host $_.Line }
}

if ($missingPassLines.Count -ne 0) {
    Write-Warning ("UART log is missing supplemental ACL evidence lines: {0}" -f ($missingPassLines -join ", "))
}

Write-Host "==== CONTROL SUMMARY ===="
Write-Host ("session_id={0}" -f $sessionId)
Write-Host ("binding_id={0}" -f $bindingId)
Write-Host ("acl_drop_count_before={0}" -f $aclDropCountBefore)
Write-Host ("acl_drop_count_after={0}" -f $aclDropCountAfter)
Write-Host ("acl_counter_delta={0}" -f ($aclDropCountAfter - $aclDropCountBefore))
Write-Host ("acl_live_reply_observed={0}" -f $liveReplyObserved)
Write-Host ("last_drop_reason_after_send={0}" -f $lastDropReasonAfterSend)
Write-Host ("last_drop_reason_after_drop={0}" -f $lastDropReasonAfterDrop)
Write-Host ("acl_hit_seen_after_send={0}" -f $aclHitSeenAfterSend)
Write-Host ("acl_hit_seen_after_drop={0}" -f $aclHitSeenAfterDrop)
$gatewayStatus.Output | ForEach-Object { Write-Host $_ }
$statusAfterSend.Output | ForEach-Object { Write-Host $_ }
$statusAfterDrop.Output | ForEach-Object { Write-Host $_ }
$status.Output | ForEach-Object { Write-Host $_ }

if ($aclFailureReason) {
    throw $aclFailureReason
}

Write-Host "ACL board check completed"

Remove-Item $captureStdout, $captureStderr -ErrorAction SilentlyContinue
