# Decrypt Function Verification Script
# Uses relative paths to avoid encoding issues

param(
    [string]$VivadoPath = "D:\Xilinx\Vivado\2024.1\bin"
)

$ErrorActionPreference = "Continue"

Write-Host "=========================================="
Write-Host " Decrypt Function Verification Script"
Write-Host "=========================================="

$env:PATH = "$VivadoPath;" + $env:PATH

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjDir = (Get-Item $ScriptDir).Parent.FullName
$SimDir = Join-Path $ProjDir "sim_output\decrypt_verify"

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

& xvlog -sv (Join-Path $TbDir "tb_crypto_engine.sv")
& xvlog -sv (Join-Path $TbDir "tb_decrypt_verification.sv")

Write-Host ""
Write-Host "=========================================="
Write-Host "Step 3: Elaborating Decrypt Test..."
Write-Host "=========================================="

& xelab -debug typical tb_decrypt_verification -snapshot decrypt_verify_snap -timescale 1ns/1ps

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Elaboration failed!"
    Write-Host "Check if encdec port is correctly connected in all modules."
    exit 1
}

Write-Host ""
Write-Host "=========================================="
Write-Host "Step 4: Running Decrypt Verification..."
Write-Host "=========================================="

& xsim decrypt_verify_snap -runall -log decrypt_verify.log

Write-Host ""
Write-Host "=========================================="
Write-Host "Step 5: Checking Results..."
Write-Host "=========================================="

$logContent = Get-Content "decrypt_verify.log" -Raw
if ($logContent -match "ALL TESTS PASSED") {
    Write-Host ""
    Write-Host "*** SUCCESS: All decrypt tests passed! ***" -ForegroundColor Green
} elseif ($logContent -match "FAIL") {
    Write-Host ""
    Write-Host "*** WARNING: Some tests failed! ***" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "*** Check decrypt_verify.log for details ***" -ForegroundColor Cyan
}

# Show test summary
Select-String -Path "decrypt_verify.log" -Pattern "PASS|FAIL|Test Summary|Passed|Failed" | ForEach-Object { Write-Host $_.Line }

Write-Host ""
Write-Host "=========================================="
Write-Host "Step 6: Running Original Encrypt Test..."
Write-Host "=========================================="

& xelab -debug typical tb_crypto_engine -snapshot encrypt_verify_snap -timescale 1ns/1ps
& xsim encrypt_verify_snap -runall -log encrypt_verify.log

Write-Host ""
Write-Host "=========================================="
Write-Host "Verification Complete!"
Write-Host "=========================================="
Write-Host "Log files location: $SimDir"
Write-Host "  - decrypt_verify.log"
Write-Host "  - encrypt_verify.log"
