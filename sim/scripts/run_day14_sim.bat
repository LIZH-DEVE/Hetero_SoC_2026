@echo off
echo ==========================================
echo Day 14: Full Integration Simulation
echo ==========================================
echo.

cd /d D:\FPGAhanjia\Hetero_SoC_2026

echo Step 1: Cleaning previous build...
if exist xsim.dir rmdir /s /q xsim.dir
if exist *.log del /q *.log
if exist *.jou del /q *.jou
echo.

echo Step 2: Compiling RTL files...
echo ----------------------------------------
call vivado -mode batch -source run_day14_sim.tcl -log day14_vivado.log

if %errorlevel% neq 0 (
    echo ERROR: Vivado simulation failed!
    exit /b 1
)

echo.
echo ==========================================
echo Day 14 Simulation Complete!
echo ==========================================
echo.

if exist tb_day14_full_integration.vcd (
    echo [OK] VCD file generated: tb_day14_full_integration.vcd
) else (
    echo [WARNING] VCD file not found
)

if exist day14_capture.pcap (
    echo [OK] Pcap file generated: day14_capture.pcap
) else (
    echo [WARNING] Pcap file not found
)

echo.
echo Verification Results:
echo ----------------------------------------
echo 1. Wireshark抓包: Check day14_capture.pcap
echo 2. Payload加密: Check simulation log
echo 3. Checksum正确: Check simulation log
echo 4. 无Malformed: Check simulation log
echo.
echo Done!
pause
