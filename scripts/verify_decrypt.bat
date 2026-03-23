@echo off
setlocal EnableDelayedExpansion

echo ==========================================
echo  Decrypt Function Verification Script
echo ==========================================

set VIVADO_BIN=D:\Xilinx\Vivado\2024.1\bin
set PATH=%VIVADO_BIN%;%PATH%

set PROJ_DIR=d:\作业\期刊\Hetero_SoC_2026
set SIM_DIR=%PROJ_DIR%\sim_output\decrypt_verify

if not exist "%SIM_DIR%" mkdir "%SIM_DIR%"
cd /d "%SIM_DIR%"

echo [INFO] Cleaning up previous runs...
if exist xsim.dir rmdir /s /q xsim.dir
if exist *.log del /q *.log
if exist *.pb del /q *.pb
if exist *.jou del /q *.jou

echo.
echo ==========================================
echo Step 1: Compiling Design Sources...
echo ==========================================

call xvlog -sv "%PROJ_DIR%\rtl\inc\sync_fifo.sv"
call xvlog -sv "%PROJ_DIR%\rtl\core\gearbox_128_to_32.sv"

call xvlog "%PROJ_DIR%\rtl\core\crypto\aes_sbox.v"
call xvlog "%PROJ_DIR%\rtl\core\crypto\aes_inv_sbox.v"
call xvlog "%PROJ_DIR%\rtl\core\crypto\aes_key_mem.v"
call xvlog "%PROJ_DIR%\rtl\core\crypto\aes_encipher_block.v"
call xvlog "%PROJ_DIR%\rtl\core\crypto\aes_decipher_block.v"
call xvlog "%PROJ_DIR%\rtl\core\crypto\aes_core.v"

call xvlog "%PROJ_DIR%\rtl\core\crypto\get_cki.v"
call xvlog "%PROJ_DIR%\rtl\core\crypto\sbox_replace.v"
call xvlog "%PROJ_DIR%\rtl\core\crypto\transform_for_encdec.v"
call xvlog "%PROJ_DIR%\rtl\core\crypto\transform_for_key_exp.v"
call xvlog "%PROJ_DIR%\rtl\core\crypto\one_round_for_encdec.v"
call xvlog "%PROJ_DIR%\rtl\core\crypto\one_round_for_key_exp.v"
call xvlog "%PROJ_DIR%\rtl\core\crypto\key_expansion.v"
call xvlog "%PROJ_DIR%\rtl\core\crypto\sm4_encdec.v"
call xvlog "%PROJ_DIR%\rtl\core\crypto\sm4_top.v"

call xvlog -sv "%PROJ_DIR%\rtl\core\crypto\crypto_core.sv"
call xvlog -sv "%PROJ_DIR%\rtl\core\crypto\crypto_engine.sv"

echo.
echo ==========================================
echo Step 2: Compiling Testbenches...
echo ==========================================

call xvlog -sv "%PROJ_DIR%\tb\tb_crypto_engine.sv"
call xvlog -sv "%PROJ_DIR%\tb\tb_decrypt_verification.sv"

echo.
echo ==========================================
echo Step 3: Elaborating Decrypt Test...
echo ==========================================

call xelab -debug typical tb_decrypt_verification -snapshot decrypt_verify_snap -timescale 1ns/1ps
if errorlevel 1 (
    echo [ERROR] Elaboration failed!
    goto :end
)

echo.
echo ==========================================
echo Step 4: Running Decrypt Verification...
echo ==========================================

call xsim decrypt_verify_snap -runall -log decrypt_verify.log

echo.
echo ==========================================
echo Step 5: Checking Results...
echo ==========================================

findstr /C:"PASS" decrypt_verify.log
findstr /C:"FAIL" decrypt_verify.log
findstr /C:"Test Summary" decrypt_verify.log

echo.
echo ==========================================
echo Step 6: Running Original Encrypt Test...
echo ==========================================

call xelab -debug typical tb_crypto_engine -snapshot encrypt_verify_snap -timescale 1ns/1ps
if errorlevel 1 (
    echo [ERROR] Elaboration failed!
    goto :end
)

call xsim encrypt_verify_snap -runall -log encrypt_verify.log

echo.
echo ==========================================
echo Verification Complete!
echo ==========================================
echo Log files location: %SIM_DIR%
echo   - decrypt_verify.log
echo   - encrypt_verify.log

:end
endlocal
pause
