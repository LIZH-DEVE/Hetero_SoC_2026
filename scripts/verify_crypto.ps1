# Comprehensive AES and SM4 Verification Script
$ErrorActionPreference = "Continue"

Write-Host "=========================================="
Write-Host " AES and SM4 Comprehensive Verification"
Write-Host "=========================================="

$VivadoBin = "D:\Xilinx\Vivado\2024.1\bin"
$env:PATH = "$VivadoBin;" + $env:PATH

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjDir = (Get-Item $ScriptDir).Parent.FullName
$SimDir = Join-Path $ProjDir "sim_output\crypto_verify"

Write-Host "[INFO] Project Dir: $ProjDir"
Write-Host "[INFO] Simulation Dir: $SimDir"

# Create simulation directory
New-Item -ItemType Directory -Force -Path $SimDir | Out-Null
Set-Location $SimDir

# Clean up
Write-Host "[INFO] Cleaning up previous runs..."
Remove-Item -Path "xsim.dir" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "*.log" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "*.pb" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "*.jou" -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=========================================="
Write-Host "Step 1: Compiling Design Sources..."
Write-Host "=========================================="

# Use relative paths from simulation directory
$RtlDir = Join-Path $ProjDir "rtl"
$TbDir = Join-Path $ProjDir "tb"

# Compile utility modules
& xvlog -sv (Join-Path $RtlDir "inc\sync_fifo.sv")
& xvlog -sv (Join-Path $RtlDir "core\gearbox_128_to_32.sv")

# Compile AES modules
$aesFiles = @(
    "aes_sbox.v", "aes_inv_sbox.v", "aes_key_mem.v",
    "aes_encipher_block.v", "aes_decipher_block.v", "aes_core.v"
)
foreach ($file in $aesFiles) {
    & xvlog (Join-Path $RtlDir "core\crypto\$file")
}

# Compile SM4 modules
$sm4Files = @(
    "get_cki.v", "sbox_replace.v", "transform_for_encdec.v",
    "transform_for_key_exp.v", "one_round_for_encdec.v",
    "one_round_for_key_exp.v", "key_expansion.v",
    "sm4_encdec.v", "sm4_top.v"
)
foreach ($file in $sm4Files) {
    & xvlog (Join-Path $RtlDir "core\crypto\$file")
}

# Compile crypto engine modules
& xvlog -sv (Join-Path $RtlDir "core\crypto\crypto_core.sv")
& xvlog -sv (Join-Path $RtlDir "core\crypto\crypto_engine.sv")

Write-Host ""
Write-Host "=========================================="
Write-Host "Step 2: Compiling Testbenches..."
Write-Host "=========================================="

& xvlog -sv (Join-Path $TbDir "tb_crypto_simple.sv")

Write-Host ""
Write-Host "=========================================="
Write-Host "Step 3: Elaborating..."
Write-Host "=========================================="

& xelab -debug typical tb_crypto_simple -snapshot crypto_verify_snap -timescale 1ns/1ps

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Elaboration failed!"
    exit 1
}

Write-Host ""
Write-Host "=========================================="
Write-Host "Step 4: Running Comprehensive Tests..."
Write-Host "=========================================="

& xsim crypto_verify_snap -runall -log crypto_verify.log

Write-Host ""
Write-Host "=========================================="
Write-Host "Step 5: Checking Results..."
Write-Host "=========================================="

$logContent = Get-Content "crypto_verify.log" -Raw
if ($logContent -match "ALL TESTS PASSED") {
    Write-Host ""
    Write-Host "*** SUCCESS: All tests passed! ***" -ForegroundColor Green
} elseif ($logContent -match "FAIL") {
    Write-Host ""
    Write-Host "*** WARNING: Some tests failed! ***" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "*** Check crypto_verify.log for details ***" -ForegroundColor Cyan
}

# Show test summary
Select-String -Path "crypto_verify.log" -Pattern "PASS|FAIL|Test Summary|Passed|Failed" | ForEach-Object { Write-Host $_.Line }

Write-Host ""
Write-Host "=========================================="
Write-Host "Verification Complete!"
Write-Host "=========================================="
Write-Host "Log files location: $SimDir"
Write-Host "  - crypto_verify.log"
