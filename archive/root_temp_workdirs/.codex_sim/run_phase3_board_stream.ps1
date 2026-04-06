[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$simDir = "D:\xsim_phase3_stream"
$vivadoBin = "D:\Xilinx\Vivado\2024.1\bin"

$xvlog = Join-Path $vivadoBin "xvlog.bat"
$xelab = Join-Path $vivadoBin "xelab.bat"
$xsim = Join-Path $vivadoBin "xsim.bat"

if (Test-Path $simDir) {
    Remove-Item -Recurse -Force $simDir
}
New-Item -ItemType Directory -Force -Path $simDir | Out-Null

$xvlogLog = Join-Path $simDir "xvlog.log"
$xelabLog = Join-Path $simDir "xelab.log"
$xsimLog = Join-Path $simDir "xsim.log"

$sources = @(
    (Join-Path $repoRoot "rtl\inc\dma_csr_pkg.sv"),
    (Join-Path $repoRoot "rtl\core\axil_csr.sv"),
    (Join-Path $repoRoot "rtl\core\dma\axis_packet_fifo_bram.sv"),
    (Join-Path $repoRoot "rtl\core\dma\dma_axis_fifo_wrapper.sv"),
    (Join-Path $repoRoot "rtl\core\dma\dma_raw_copy_engine.sv"),
    (Join-Path $repoRoot "rtl\core\dma\dma_desc_fetcher.sv"),
    (Join-Path $repoRoot "rtl\core\dma\stream_dummy_source.sv"),
    (Join-Path $repoRoot "rtl\top\dma_raw_copy_subsystem.sv"),
    (Join-Path $repoRoot "rtl\top\dma_stream_smoke_board_wrapper.v"),
    (Join-Path $repoRoot "tb\tb_dma_stream_smoke_board_wrapper.sv")
)

Push-Location $simDir
try {
    & $xvlog --sv --log $xvlogLog @sources
    if ($LASTEXITCODE -ne 0) {
        Get-Content $xvlogLog
        throw "xvlog failed"
    }

    & $xelab work.tb_dma_stream_smoke_board_wrapper `
        -s tb_dma_stream_smoke_board_wrapper `
        --timescale 1ns/1ps `
        -debug typical `
        --log $xelabLog
    if ($LASTEXITCODE -ne 0) {
        Get-Content $xelabLog
        throw "xelab failed"
    }

    & $xsim tb_dma_stream_smoke_board_wrapper -runall --log $xsimLog
    if ($LASTEXITCODE -ne 0) {
        Get-Content $xsimLog
        throw "xsim failed"
    }

    Get-Content $xsimLog
}
finally {
    Pop-Location
}
