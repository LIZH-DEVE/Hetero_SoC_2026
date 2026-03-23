[CmdletBinding()]
param(
    [string]$XsctPath = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat"
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildTcl = Join-Path $workspace "build_ax7020_official_net_test.tcl"
$officialWs = Join-Path $workspace "ax7020_official_net_test"

if (-not (Test-Path $XsctPath)) {
    throw "XSCT not found: $XsctPath"
}
if (-not (Test-Path $buildTcl)) {
    throw "build Tcl not found: $buildTcl"
}

if (Test-Path $officialWs) {
    Remove-Item -Recurse -Force $officialWs
}

$stdout = New-TemporaryFile
$stderr = New-TemporaryFile
try {
    $proc = Start-Process -FilePath $XsctPath -ArgumentList $buildTcl -PassThru -Wait -NoNewWindow `
        -RedirectStandardOutput $stdout.FullName -RedirectStandardError $stderr.FullName
    $out = if (Test-Path $stdout.FullName) { Get-Content $stdout.FullName -Raw } else { "" }
    $err = if (Test-Path $stderr.FullName) { Get-Content $stderr.FullName -Raw } else { "" }
    if ($out) { Write-Host $out.TrimEnd() }
    if ($err) { Write-Host $err.TrimEnd() }
    if ($proc.ExitCode -ne 0 -or $out -notmatch 'OFFICIAL_NET_TEST_BUILD_DONE') {
        throw "Official AX7020 net_test build failed."
    }
} finally {
    Remove-Item $stdout.FullName, $stderr.FullName -Force -ErrorAction SilentlyContinue
}

$elf = Join-Path $officialWs "net_test_system\Debug\net_test.elf"
if (-not (Test-Path $elf)) {
    $elf = Join-Path $officialWs "net_test\Debug\net_test.elf"
}
if (-not (Test-Path $elf)) {
    throw "Build completed but net_test.elf was not found under $officialWs"
}

Write-Host "Built official AX7020 net_test:"
Write-Host $elf
