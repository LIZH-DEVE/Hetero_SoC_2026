[CmdletBinding()]
param(
    [string]$Port = "COM9",

    [ValidateSet(115200, 230400)]
    [int]$Baud = 115200,

    [int]$CaptureSeconds = 120,

    [int]$BootLeadSeconds = 20,

    [string]$TargetIp = "192.168.1.20",

    [string]$SourceIp = "192.168.1.11",

    [int]$BenchRepeats = 1000,

    [string]$SdDrive,

    [switch]$Deploy,

    [switch]$AssumeRunning
)

$ErrorActionPreference = "Stop"

# run_ax7020_udp_gateway_shadow_mirror_performance_check.ps1
$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $workspace
$captureScript = Join-Path $workspace "capture_uart_boot_log.ps1"
$deployScript = Join-Path $workspace "deploy_ax7020_udp_gateway_shadow_mirror_to_sd.ps1"
$benchScript = Join-Path $repoRoot "scripts\day21_performance_benchmark.py"
$releaseBootBin = Join-Path $workspace "sd_boot\ax7020_udp_gateway_shadow_mirror\BOOT.BIN"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$uartLogPath = Join-Path $repoRoot ("board_uart_boot_{0}_{1}.txt" -f $Baud, $stamp)
$captureStdout = Join-Path $env:TEMP ("shadow_perf_capture_stdout_{0}.txt" -f $stamp)
$captureStderr = Join-Path $env:TEMP ("shadow_perf_capture_stderr_{0}.txt" -f $stamp)
$reportDir = Join-Path $repoRoot ("doc\reports\board_benchmarks\shadow_mirror_{0}" -f $stamp)
$pythonExe = (Get-Command python.exe -ErrorAction Stop).Source

if (-not (Test-Path $releaseBootBin)) {
    throw "Release BOOT.BIN not found: $releaseBootBin"
}
if (-not (Test-Path $benchScript)) {
    throw "Benchmark helper not found: $benchScript"
}

$expectedHash = (Get-FileHash $releaseBootBin -Algorithm SHA256).Hash.ToUpperInvariant()

function Normalize-PathEnvironment {
    $processEnv = [System.Environment]::GetEnvironmentVariables('Process')
    if ($processEnv.Contains('Path') -and $processEnv.Contains('PATH')) {
        [System.Environment]::SetEnvironmentVariable('PATH', $null, 'Process')
    }
}

function Invoke-PythonLogged {
    param(
        [string]$Label,
        [string[]]$Arguments
    )

    Write-Host ("==== {0} ====" -f $Label)
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $pythonExe `
            -ArgumentList $Arguments `
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
    Write-Host ("Waiting {0} seconds before sending BENCH control traffic..." -f $BootLeadSeconds)
    Start-Sleep -Seconds $BootLeadSeconds
}

$result = Invoke-PythonLogged -Label "PERF" -Arguments @(
    $benchScript,
    "--bench-ip", $TargetIp,
    "--source-ip", $SourceIp,
    "--control-port", "4662",
    "--control-timeout", "3",
    "--algos", "aes,sm4",
    "--repeats", "$BenchRepeats",
    "--target-speedup", "1.0",
    "--output-dir", $reportDir
)
if (($result.ExitCode -ne 0) -and ($result.ExitCode -ne 2)) {
    throw "Performance benchmark helper failed with exit code $($result.ExitCode)"
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

$summaryPath = Join-Path $reportDir "board_bench_summary.md"
$jsonPath = Join-Path $reportDir "board_bench_report.json"
$uartText = Get-Content $uartLogPath -Raw
$requiredPassLines = @(
    "LIVE_CTRL PASS"
)
$missingPassLines = @(
    $requiredPassLines | Where-Object { $uartText.IndexOf($_, [System.StringComparison]::Ordinal) -lt 0 }
)

Write-Host "==== UART KEY LINES ===="
$uartText |
    Select-String "UDP crypto gateway started @ ports 4660\(AES\) 4661\(SM4\) 4662\(CTRL\)|LIVE_CTRL PASS|LIVE_AES PASS|LIVE_SM4 PASS|SHADOW_AES PASS|SHADOW_SM4 PASS|SHADOW_INVALID_SKIP PASS|UDP gateway shadow mirror PASS" |
    ForEach-Object { Write-Host $_.Line }

if ($missingPassLines.Count -ne 0) {
    Write-Warning ("UART log is missing supplemental performance evidence lines: {0}" -f ($missingPassLines -join ", "))
}

if (Test-Path $summaryPath) {
    Write-Host "==== BENCH MARKDOWN SUMMARY ===="
    Get-Content $summaryPath | ForEach-Object { Write-Host $_ }
}

if (Test-Path $jsonPath) {
    Write-Host "==== BENCH JSON PATH ===="
    Write-Host $jsonPath
}

if (-not (Test-Path $jsonPath)) {
    throw "Benchmark JSON report was not created: $jsonPath"
}

$benchReport = Get-Content $jsonPath -Raw | ConvertFrom-Json
$targetSpeedup = [double]$benchReport.target.speedup
$aesAvg = [double]$benchReport.results.aes.summary.avg_speedup
$sm4Avg = [double]$benchReport.results.sm4.summary.avg_speedup

if (($aesAvg -lt $targetSpeedup) -or ($sm4Avg -lt $targetSpeedup)) {
    throw ("Performance target not met: target={0:N6}x AES avg_speedup={1:N6}x SM4 avg_speedup={2:N6}x" -f $targetSpeedup, $aesAvg, $sm4Avg)
}

if ($result.ExitCode -eq 2) {
    throw "Performance benchmark helper reported a target miss without a matching JSON failure condition"
}

Write-Host "==== UART FULL LOG ===="
Write-Host $uartText

Remove-Item $captureStdout, $captureStderr -ErrorAction SilentlyContinue
