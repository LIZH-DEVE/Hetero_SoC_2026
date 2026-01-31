@echo off
setlocal enabledelayedexpansion

echo ================================================================================
echo Day 15: Hardware Security Module (HSM) Simulation
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
call vivado -mode batch -source run_day15_sim.tcl -log day15_vivado.log

if %errorlevel% neq 0 (
    echo ERROR: Vivado simulation failed!
    exit /b 1
)

echo.
echo ================================================================================
echo Day 15 Simulation Complete!
echo ================================================================================
echo.

if exist tb_day15_hsm.vcd (
    echo [OK] VCD file generated: tb_day15_hsm.vcd
) else (
    echo [WARNING] VCD file not found
)

echo.
echo Test Results:
echo ----------------------------------------
echo Task 14.1: Config Packet Auth
echo   - Magic Number Authentication: Check simulate.log
echo   - Anti-Replay Protection: Check simulate.log
echo.
echo Task 14.2: Key Vault with DNA Binding
echo   - DNA Binding: Check simulate.log
echo   - Key Derivation: Check simulate.log
echo   - System Lock: Check simulate.log
echo.
echo View Waveform:
echo   GTKWave: gtkwave tb_day15_hsm.vcd
echo.
echo Done!
pause
