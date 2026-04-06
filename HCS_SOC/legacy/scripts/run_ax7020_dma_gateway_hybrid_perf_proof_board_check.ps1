[CmdletBinding()]
param(
    [string]$Port = "COM9",

    [ValidateSet(115200, 230400)]
    [int]$Baud = 115200,

    [int]$CaptureSeconds = 120,

    [int]$BootLeadSeconds = 20,

    [int]$BenchRepeats = 1000,

    [string]$SdDrive,

    [switch]$Deploy
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $workspace
$captureScript = Join-Path $workspace "capture_uart_boot_log.ps1"
$deployScript = Join-Path $workspace "deploy_ax7020_dma_gateway_hybrid_perf_proof_to_sd.ps1"
$benchScript = Join-Path $repoRoot "scripts\day21_performance_benchmark.py"
$releaseBootBin = Join-Path $workspace "sd_boot\ax7020_dma_gateway_hybrid_perf_proof\BOOT.BIN"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$uartLogPath = Join-Path $repoRoot ("board_uart_boot_{0}_{1}.txt" -f $Baud, $stamp)
$captureStdout = Join-Path $env:TEMP ("hybrid_perf_proof_capture_stdout_{0}.txt" -f $stamp)
$captureStderr = Join-Path $env:TEMP ("hybrid_perf_proof_capture_stderr_{0}.txt" -f $stamp)
$reportDir = Join-Path $repoRoot ("doc\reports\board_benchmarks\hybrid_perf_proof_{0}" -f $stamp)

if (-not (Test-Path $releaseBootBin)) {
    throw "Perf proof BOOT.BIN not found: $releaseBootBin"
}

if ($Deploy) {
    if (-not $SdDrive) {
        throw "-Deploy requires -SdDrive, for example -SdDrive E:"
    }
    & $deployScript -SdDrive $SdDrive
}

function Invoke-PythonLogged {
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
Write-Host "Power-cycle the board now: turn power off for 3 seconds, then power it back on."
Write-Host ("Waiting {0} seconds for the Stage 2 proof image to run on UART..." -f $BootLeadSeconds)
Start-Sleep -Seconds $BootLeadSeconds

Wait-Process -Id $captureProc.Id

Write-Host "==== CAPTURE SCRIPT OUTPUT ===="
if (Test-Path $captureStdout) {
    Get-Content $captureStdout | ForEach-Object { Write-Host $_ }
}
if (Test-Path $captureStderr) {
    $stderrLines = Get-Content $captureStderr
    if ($stderrLines.Count -gt 0) {
        Write-Host "stderr:"
        $stderrLines | ForEach-Object { Write-Host $_ }
    }
}

$uartText = if (Test-Path $uartLogPath) { Get-Content $uartLogPath -Raw } else { "" }
$requiredPassLines = @(
    "PROOF_AES PASS",
    "PROOF_SM4 PASS",
    "DMA gateway hybrid perf proof PASS"
)
$missingPassLines = @(
    $requiredPassLines | Where-Object { $uartText -notlike "*$_*" }
)
if ($missingPassLines.Count -ne 0) {
    throw ("UART proof log is missing required PASS lines: {0}" -f ($missingPassLines -join ", "))
}

$benchResult = Invoke-PythonLogged -Label "PERF" -Arguments @(
    $benchScript,
    "--proof-uart-log", $uartLogPath,
    "--expected-proof-repeats", "$BenchRepeats",
    "--target-speedup", "1.0",
    "--output-dir", $reportDir
)
$benchExit = $benchResult.ExitCode

$summaryPath = Join-Path $reportDir "board_bench_summary.md"
$jsonPath = Join-Path $reportDir "board_bench_report.json"

Write-Host "==== UART KEY LINES ===="
if (Test-Path $uartLogPath) {
    Select-String -Path $uartLogPath -Pattern "AX7020 DMA gateway hybrid perf proof image|PROOF_CONFIG|PROOF_ROW|PROOF_AES PASS|PROOF_SM4 PASS|DMA gateway hybrid perf proof PASS" |
        ForEach-Object { Write-Host $_.Line }
} else {
    Write-Host "UART log missing"
}

Write-Host "==== BENCH MARKDOWN SUMMARY ===="
if (Test-Path $summaryPath) {
    Get-Content $summaryPath | ForEach-Object { Write-Host $_ }
} else {
    Write-Host "single-launch SG batch summary missing"
}

Write-Host "==== BENCH JSON PATH ===="
Write-Host $jsonPath

if (Test-Path $jsonPath) {
    $benchReport = Get-Content $jsonPath -Raw | ConvertFrom-Json
    Write-Host ("Descriptor count: {0}" -f $benchReport.results.aes.diagnostics.batch_descriptor_count)
    Write-Host ("Doorbell count: {0}" -f $benchReport.results.aes.diagnostics.doorbell_count)
}

if ($benchExit -ne 0) {
    throw "Hybrid perf proof benchmark helper failed with exit code $benchExit"
}
