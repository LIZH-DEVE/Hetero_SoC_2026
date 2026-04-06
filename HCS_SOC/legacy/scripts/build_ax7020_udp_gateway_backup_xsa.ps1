[CmdletBinding()]
param(
    [string]$XsctPath = "D:\Xilinx\Vitis\2023.1\bin\xsct.bat"
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildTcl = Join-Path $workspace "build_ax7020_udp_gateway_backup_xsa.tcl"
$backupWs = Join-Path $workspace "vitis_2023_udp_gateway_backup_xsa_ws"
$fsbl = Join-Path $backupWs "ax7020_udp_gateway_backup_platform\zynq_fsbl\fsbl.elf"
$spec = Join-Path $backupWs "ax7020_udp_gateway_backup_platform\zynq_fsbl\Xilinx.spec"
$xparams = Join-Path $backupWs "ax7020_udp_gateway_backup_platform\zynq_fsbl\zynq_fsbl_bsp\ps7_cortexa9_0\include\xparameters.h"
$libxil = Join-Path $backupWs "ax7020_udp_gateway_backup_platform\zynq_fsbl\zynq_fsbl_bsp\ps7_cortexa9_0\lib\libxil.a"

if (-not (Test-Path $XsctPath)) {
    throw "XSCT not found: $XsctPath"
}
if (-not (Test-Path $buildTcl)) {
    throw "build Tcl not found: $buildTcl"
}

if (Test-Path $backupWs) {
    Remove-Item -Recurse -Force $backupWs
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
    if ($proc.ExitCode -ne 0 -or $out -notmatch 'BACKUP_XSA_BUILD_DONE') {
        throw "Backup-XSA AX7020 platform build failed."
    }
} finally {
    Remove-Item $stdout.FullName, $stderr.FullName -Force -ErrorAction SilentlyContinue
}

foreach ($pathInfo in @(
    @{ Label = "Backup platform FSBL"; Path = $fsbl },
    @{ Label = "Backup Xilinx.spec"; Path = $spec },
    @{ Label = "Backup xparameters.h"; Path = $xparams },
    @{ Label = "Backup libxil.a"; Path = $libxil }
)) {
    if (-not (Test-Path $pathInfo.Path)) {
        throw "$($pathInfo.Label) not found: $($pathInfo.Path)"
    }
}

Write-Host "Built backup-XSA AX7020 workspace:"
Write-Host $backupWs
