[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReportPath,
    [switch]$FailIfViolating,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ReportPath)) {
    throw "Timing summary report not found: $ReportPath"
}

$content = Get-Content -Path $ReportPath -Raw

$setupMatch = [regex]::Match(
    $content,
    'Setup\s*:\s*(\d+)\s+Failing Endpoints,\s+Worst Slack\s+(-?\d+\.\d+)ns,\s+Total Violation\s+(-?\d+\.\d+)ns'
)
$holdMatch = [regex]::Match(
    $content,
    'Hold\s*:\s*(\d+)\s+Failing Endpoints,\s+Worst Slack\s+(-?\d+\.\d+)ns,\s+Total Violation\s+(-?\d+\.\d+)ns'
)

if (-not $setupMatch.Success) {
    throw "Could not parse setup timing summary from: $ReportPath"
}
if (-not $holdMatch.Success) {
    throw "Could not parse hold timing summary from: $ReportPath"
}

$result = [pscustomobject]@{
    ReportPath            = (Resolve-Path $ReportPath).Path
    SetupFailingEndpoints = [int]$setupMatch.Groups[1].Value
    SetupWnsNs            = [double]$setupMatch.Groups[2].Value
    SetupTnsNs            = [double]$setupMatch.Groups[3].Value
    HoldFailingEndpoints  = [int]$holdMatch.Groups[1].Value
    HoldWhsNs             = [double]$holdMatch.Groups[2].Value
    HoldThsNs             = [double]$holdMatch.Groups[3].Value
}

$timingClean = (
    $result.SetupFailingEndpoints -eq 0 -and
    $result.SetupWnsNs -ge 0.0 -and
    $result.SetupTnsNs -eq 0.0 -and
    $result.HoldFailingEndpoints -eq 0 -and
    $result.HoldWhsNs -ge 0.0 -and
    $result.HoldThsNs -eq 0.0
)

$result | Add-Member -NotePropertyName TimingClean -NotePropertyValue $timingClean

if (-not $Quiet) {
    Write-Host "Timing summary:"
    Write-Host "  report     = $($result.ReportPath)"
    Write-Host "  setup WNS  = $($result.SetupWnsNs) ns"
    Write-Host "  setup TNS  = $($result.SetupTnsNs) ns"
    Write-Host "  setup fail = $($result.SetupFailingEndpoints)"
    Write-Host "  hold WHS   = $($result.HoldWhsNs) ns"
    Write-Host "  hold THS   = $($result.HoldThsNs) ns"
    Write-Host "  hold fail  = $($result.HoldFailingEndpoints)"
    Write-Host "  clean      = $timingClean"
}

if ($FailIfViolating -and -not $timingClean) {
    throw "Timing gate failed for $($result.ReportPath): setup WNS=$($result.SetupWnsNs)ns TNS=$($result.SetupTnsNs)ns fail=$($result.SetupFailingEndpoints); hold WHS=$($result.HoldWhsNs)ns THS=$($result.HoldThsNs)ns fail=$($result.HoldFailingEndpoints)"
}

$result
