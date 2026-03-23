[CmdletBinding()]
param(
    [ValidateSet("program")]
    [string]$Action = "program",
    [string]$XsdbPath = "D:\Xilinx\Vitis\2024.1\bin\xsdb.bat"
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $workspace "download_ax7020_official_net_test.tcl"

if (-not (Test-Path $XsdbPath)) {
    throw "xsdb not found: $XsdbPath"
}
if (-not (Test-Path $scriptPath)) {
    throw "download script not found: $scriptPath"
}

$stdout = New-TemporaryFile
$stderr = New-TemporaryFile
try {
    Write-Host "[program attempt 1]"
    $proc = Start-Process -FilePath $XsdbPath -ArgumentList $scriptPath -PassThru -Wait -NoNewWindow `
        -RedirectStandardOutput $stdout.FullName -RedirectStandardError $stderr.FullName
    $out = if (Test-Path $stdout.FullName) { Get-Content $stdout.FullName -Raw } else { "" }
    $err = if (Test-Path $stderr.FullName) { Get-Content $stderr.FullName -Raw } else { "" }
    if ($out) { Write-Host $out.TrimEnd() }
    if ($err) { Write-Host $err.TrimEnd() }
    if ($proc.ExitCode -ne 0 -or $out -notmatch 'PROGRAM_DONE') {
        throw "official net_test program failed"
    }
} finally {
    Remove-Item $stdout.FullName, $stderr.FullName -Force -ErrorAction SilentlyContinue
}
