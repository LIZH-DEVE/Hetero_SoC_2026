@echo off
REM Day 1-13 Verification Batch Script
REM Run from: D:\FPGAhanjia\Hetero_SoC_2026\HCS_SOC

echo ==========================================
echo Day 1-13 Verification
echo ==========================================

set RTL_DIR=D:\FPGAhanjia\Hetero_SoC_2026\rtl
set TB_DIR=D:\FPGAhanjia\Hetero_SoC_2026\tb

echo [1] Checking file existence...
echo ==========================================

if exist "%RTL_DIR%\core\dma\dma_s2mm_mm2s_engine.sv" (
    echo OK: dma_s2mm_mm2s_engine.sv exists
) else (
    echo ERROR: dma_s2mm_mm2s_engine.sv missing
)

if exist "%RTL_DIR%\top\crypto_dma_subsystem.sv" (
    echo OK: crypto_dma_subsystem.sv exists
) else (
    echo ERROR: crypto_dma_subsystem.sv missing
)

if exist "%RTL_DIR%\core\parser\rx_parser.sv" (
    echo OK: rx_parser.sv exists
) else (
    echo ERROR: rx_parser.sv missing
)

echo.
echo [2] Checking module names...
echo ==========================================

findstr /C:"module dma_s2mm_mm2s_engine" "%RTL_DIR%\core\dma\dma_s2mm_mm2s_engine.sv" >nul
if %errorlevel% equ 0 (
    echo OK: Module name is dma_s2mm_mm2s_engine
) else (
    echo ERROR: Module name mismatch!
)

echo.
echo [3] Checking key fixes...
echo ==========================================

findstr /C:"Alignment check" "%RTL_DIR%\core\parser\rx_parser.sv" >nul
if %errorlevel% equ 0 (
    echo OK: rx_parser alignment check found
) else (
    echo ERROR: rx_parser alignment check NOT found
)

findstr /C:"m_axis_wvalid" "%RTL_DIR%\top\crypto_dma_subsystem.sv" >nul
if %errorlevel% equ 0 (
    echo OK: crypto_dma_subsystem m_axis_wvalid found
) else (
    echo ERROR: crypto_dma_subsystem m_axis_wvalid MISSING
)

echo.
echo [4] Running syntax check...
echo ==========================================

"D:\Xilinx\Vivado\2024.1\bin\xvlog.exe" -sv "%RTL_DIR%\core\dma\dma_s2mm_mm2s_engine.sv"
"D:\Xilinx\Vivado\2024.1\bin\xvlog.exe" -sv "%RTL_DIR%\top\crypto_dma_subsystem.sv"
"D:\Xilinx\Vivado\2024.1\bin\xvlog.exe" -sv "%RTL_DIR%\core\parser\rx_parser.sv"

echo.
echo ==========================================
echo Verification Complete!
echo ==========================================
pause
