@echo off
setlocal enabledelayedexpansion

echo ================================================================================
echo Day 16: Hardware Firewall (ACL) Simulation
echo ================================================================================
echo.

cd /d D:\FPGAhanjia\Hetero_SoC_2026

echo Step 1: Cleaning previous build...
if exist xsim.dir rmdir /s /q xsim.dir
if exist *.log del /q *.log
if exist *.jou del /q *.jou
if exist *.vcd del /q *.vcd
echo.

echo Step 2: Compiling RTL files...
echo ----------------------------------------
call vivado -mode batch -source run_day16_sim.tcl -log day16_vivado.log

if %errorlevel% neq 0 (
    echo ERROR: Vivado simulation failed!
    exit /b 1
)

echo.
echo ================================================================================
echo Day 16 Simulation Complete!
echo ================================================================================
echo.

if exist tb_day16_acl.vcd (
    echo [OK] VCD file generated: tb_day16_acl.vcd
) else (
    echo [WARNING] VCD file not found
)

echo.
echo Test Results:
echo ----------------------------------------
echo Task 15.1: 5-Tuple Extraction
echo   - Check simulate.log for details
echo.
echo Task 15.2: Enhanced Match Engine
echo   - Check simulate.log for details
echo.
echo View Waveform:
echo   GTKWave: gtkwave tb_day16_acl.vcd
echo.
echo Done!
pause
