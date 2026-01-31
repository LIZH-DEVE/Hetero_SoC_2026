@echo off
echo ========================================
echo Day 17: Zero-Copy FastPath Simulation
echo ========================================
echo.

cd /d "D:\FPGAhanjia\Hetero_SoC_2026"

echo [1] Compiling design...
"D:\Xilinx\Vivado\2024.1\bin\unwrapped\win64.o\xelab.exe" -debug typical -sv ../rtl/core/fast_path.sv ../tb/tb_day17_fastpath.sv -s day17_sim_snapshot

if %ERRORLEVEL% NEQ 0 (
    echo Compilation failed!
    exit /b 1
)

echo [2] Running simulation...
"D:\Xilinx\Vivado\2024.1\bin\unwrapped\win64.o\xsim.exe" day17_sim_snapshot -runall

echo.
echo ========================================
echo Simulation complete!
echo ========================================
