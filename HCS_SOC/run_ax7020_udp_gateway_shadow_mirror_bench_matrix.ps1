[CmdletBinding()]
param(
    [string]$Port = "COM9",

    [int]$Baud = 115200,

    [string]$TargetIp = "192.168.1.20",

    [string]$SourceIp = "192.168.1.11",

    [int]$BootLeadSeconds = 20,

    [int]$RequestsPerScenario = 200,

    [int]$BenchRepeats = 1000,

    [switch]$AssumeRunning
)

$ErrorActionPreference = "Stop"

# run_ax7020_udp_gateway_shadow_mirror_bench_matrix.ps1
$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $workspace
$captureScript = Join-Path $workspace "capture_uart_boot_log.ps1"
$benchScript = Join-Path $repoRoot "scripts\day21_benchmark_matrix.py"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$captureSeconds = 120
$uartLogPath = Join-Path $repoRoot ("board_uart_boot_{0}_{1}.txt" -f $Baud, $stamp)
$captureStdout = Join-Path $env:TEMP ("shadow_bench_matrix_capture_stdout_{0}.txt" -f $stamp)
$captureStderr = Join-Path $env:TEMP ("shadow_bench_matrix_capture_stderr_{0}.txt" -f $stamp)
$reportDir = Join-Path $repoRoot ("doc\reports\board_bench_matrix\shadow_mirror_{0}" -f $stamp)
$summaryPath = Join-Path $reportDir "bench_matrix_summary.md"
$jsonPath = Join-Path $reportDir "bench_matrix_report.json"
$csvPath = Join-Path $reportDir "bench_matrix_results.csv"
$captureProc = $null

if (-not (Test-Path $captureScript)) {
    throw "UART capture helper not found: $captureScript"
}
if (-not (Test-Path $benchScript)) {
    throw "Benchmark matrix helper not found: $benchScript"
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

try {
    $captureArgs = @(
        "-ExecutionPolicy", "Bypass",
        "-File", $captureScript,
        "-Port", $Port,
        "-Baud", $Baud,
        "-TimeoutSeconds", $captureSeconds,
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
        Write-Host ("Waiting {0} seconds before sending benchmark matrix control traffic..." -f $BootLeadSeconds)
        Start-Sleep -Seconds $BootLeadSeconds
    }

    $result = Invoke-PythonLogged -Label "BENCH_MATRIX" -Arguments @(
        $benchScript,
        "--target-ip", $TargetIp,
        "--source-ip", $SourceIp,
        "--requests-per-scenario", "$RequestsPerScenario",
        "--repeats", "$BenchRepeats",
        "--output-dir", $reportDir
    )
    if ($result.ExitCode -ne 0) {
        throw "Benchmark matrix helper failed with exit code $($result.ExitCode)"
    }
}
finally {
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

    Remove-Item $captureStdout, $captureStderr -ErrorAction SilentlyContinue
}

if (-not (Test-Path $uartLogPath)) {
    throw "UART log file was not created: $uartLogPath"
}

$uartText = Get-Content $uartLogPath -Raw
$bootBannerLines = @(
    "UDP gateway shadow mirror image",
    "UDP crypto gateway started @ ports 4660(AES) 4661(SM4) 4662(CTRL)"
)
$missingBootBannerLines = @(
    $bootBannerLines | Where-Object { $uartText.IndexOf($_, [System.StringComparison]::Ordinal) -lt 0 }
)
$uartHardFailPatterns = @(
    "shadow compare fail",
    "SHADOW_FASTPATH FALLBACK"
)
$uartHardFailHits = @(
    $uartHardFailPatterns | Where-Object { $uartText.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }
)

Write-Host "==== UART KEY LINES ===="
$uartText |
    Select-String "UDP gateway shadow mirror image|UDP crypto gateway started @ ports 4660\(AES\) 4661\(SM4\) 4662\(CTRL\)|LIVE_CTRL PASS|LIVE_AES PASS|LIVE_SM4 PASS|SHADOW_AES PASS|SHADOW_SM4 PASS|SHADOW_INVALID_SKIP PASS|SHADOW_FASTPATH FALLBACK|shadow compare fail|UDP gateway shadow mirror PASS" |
    ForEach-Object { Write-Host $_.Line }

if ($missingBootBannerLines.Count -ne 0) {
    Write-Warning ("UART log is missing supplemental boot banner lines: {0}" -f ($missingBootBannerLines -join ", "))
}
if ($uartHardFailHits.Count -gt 0) {
    throw ("UART log contains hard-fail lines: {0}" -f ($uartHardFailHits -join ", "))
}

Write-Host "==== BENCH MATRIX ARTIFACTS ===="
Write-Host ("bench_matrix_report.json: {0}" -f $jsonPath)
Write-Host ("bench_matrix_summary.md: {0}" -f $summaryPath)
Write-Host ("bench_matrix_results.csv: {0}" -f $csvPath)

foreach ($artifactPath in @($jsonPath, $summaryPath, $csvPath)) {
    if (-not (Test-Path $artifactPath)) {
        throw "Benchmark matrix artifact was not created: $artifactPath"
    }
}

Write-Host "==== UART FULL LOG ===="
Write-Host $uartText
