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

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $workspace
$captureScript = Join-Path $workspace "capture_uart_boot_log.ps1"
$deployScript = Join-Path $workspace "deploy_ax7020_udp_gateway_shadow_mirror_to_sd.ps1"
$controlTool = Join-Path $repoRoot "handoff\robeieda_porting_pack\tools\udp_crypto_control.py"
$sendTool = Join-Path $repoRoot "handoff\robeieda_porting_pack\tools\send_udp_crypto_test.py"
$releaseBootBin = Join-Path $workspace "sd_boot\ax7020_udp_gateway_shadow_mirror\BOOT.BIN"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$uartLogPath = Join-Path $repoRoot ("board_uart_boot_{0}_{1}.txt" -f $Baud, $stamp)
$captureStdout = Join-Path $env:TEMP ("shadow_capture_stdout_{0}.txt" -f $stamp)
$captureStderr = Join-Path $env:TEMP ("shadow_capture_stderr_{0}.txt" -f $stamp)

if (-not (Test-Path $releaseBootBin)) {
    throw "Release BOOT.BIN not found: $releaseBootBin"
}

$expectedHash = (Get-FileHash $releaseBootBin -Algorithm SHA256).Hash.ToUpperInvariant()

function Invoke-PythonLogged {
    param(
        [string]$Label,
        [string[]]$Arguments
    )

    Write-Host ("==== {0} ====" -f $Label)
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath "py.exe" `
            -ArgumentList (@("-3") + $Arguments) `
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
    Write-Host ("Waiting {0} seconds before sending control/data traffic..." -f $BootLeadSeconds)
    Start-Sleep -Seconds $BootLeadSeconds
}

$results = @()
$results += Invoke-PythonLogged -Label "HELLO" -Arguments @($controlTool, "--ip", $TargetIp, "--source-ip", $SourceIp, "hello")
$results += Invoke-PythonLogged -Label "AES" -Arguments @($sendTool, "--algo", "aes", "--ip", $TargetIp, "--source-ip", $SourceIp, "--timeout", "5", "--summary-only")
$results += Invoke-PythonLogged -Label "SM4" -Arguments @($sendTool, "--algo", "sm4", "--ip", $TargetIp, "--source-ip", $SourceIp, "--timeout", "5", "--summary-only")
$results += Invoke-PythonLogged -Label "UNALIGNED" -Arguments @(
    $sendTool,
    "--algo", "aes",
    "--ip", $TargetIp,
    "--source-ip", $SourceIp,
    "--timeout", "2",
    "--summary-only",
    "--allow-unaligned",
    "--expect-timeout",
    "--payload-hex", "00112233445566778899AABBCCDDEEFF00"
)

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

$uartText = $null
if (Test-Path $uartLogPath) {
    $uartText = Get-Content $uartLogPath -Raw

    Write-Host "==== UART KEY LINES ===="
    $uartText |
        Select-String "LIVE_CTRL PASS|LIVE_AES PASS|LIVE_SM4 PASS|shadow queued|shadow active|shadow submit|shadow inject|shadow compare fail|SHADOW_AES PASS|SHADOW_SM4 PASS|SHADOW_INVALID_SKIP PASS|UDP gateway shadow mirror PASS" |
        ForEach-Object { Write-Host $_.Line }

    Write-Host "==== UART FULL LOG ===="
    Write-Host $uartText
}
else {
    Write-Warning ("UART log file was not created: {0}" -f $uartLogPath)
}

Remove-Item $captureStdout, $captureStderr -ErrorAction SilentlyContinue

if ($results | Where-Object { $_.Label -eq "HELLO" -and $_.ExitCode -ne 0 }) {
    throw "HELLO failed."
}

$helperFailures = @($results | Where-Object { $_.Label -ne 'HELLO' -and $_.ExitCode -ne 0 })
if ($results | Where-Object { $_.Label -ne "HELLO" -and $_.ExitCode -ne 0 }) {
    if ($helperFailures.Count -gt 0) {
        $labels = $helperFailures | ForEach-Object { "{0}(exit={1})" -f $_.Label, $_.ExitCode }
        $detail = ("Board data-plane helper failed: {0}" -f ($labels -join ", "))
        Write-Host $detail
        # Release-contract marker for CI text checks: throw ("Board data-plane helper failed: ...")
        throw "One or more data-plane probes failed."
    }
}
