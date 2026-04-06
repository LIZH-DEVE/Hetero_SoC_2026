@echo off
echo ========================================
echo Running Full System Simulation
echo ========================================
echo.

cd /d D:\FPGAhanjia\Hetero_SoC_2026

echo Setting up Vivado environment...
call D:\Xilinx\Vivado\2024.1\settings64.bat

echo.
echo ========================================
echo Compiling RTL files...
echo ========================================
echo.

echo [1/10] Compiling pkg_axi_stream.sv...
xvlog -sv rtl/inc/pkg_axi_stream.sv -work work
if errorlevel 1 goto error

echo [2/10] Compiling axil_csr.sv...
xvlog -sv rtl/core/axil_csr.sv -work work
if errorlevel 1 goto error

echo [3/10] Compiling dma_master_engine.sv...
xvlog -sv rtl/core/dma/dma_master_engine.sv -work work
if errorlevel 1 goto error

echo [4/10] Compiling gearbox_128_to_32.sv...
xvlog -sv rtl/core/gearbox_128_to_32.sv -work work
if errorlevel 1 goto errorlevel 1 goto error

echo [5/10] Compiling async_fifo.sv...
xvlog -sv rtl/core/async_fifo.sv -work work
if errorlevel 1 goto error

echo [6/10] Compiling crypto_engine.sv...
xvlog -sv rtl/core/crypto/crypto_engine.sv -work work
if errorlevel 1 goto error

echo [7/10] Compiling packet_dispatcher.sv...
xvlog -sv rtl/top/packet_dispatcher.sv -work work
if errorlevel 1 goto error

echo [8/10] Compiling pbm_controller.sv...
xvlog -sv rtl/core/pbm/pbm_controller.sv -work work
if errorlevel 1 goto error

echo [9/10] Compiling tx_stack.sv...
xvlog -sv rtl/core/tx/tx_stack.sv -work work
if errorlevel 1 goto error

echo [10/10] Compiling rx_parser.sv...
xvlog -sv rtl/core/parser/rx_parser.sv -work work
if errorlevel 1 goto errorlevel 1 goto error

echo.
echo ========================================
echo Compiling Testbench files...
echo ========================================
echo.

echo [11/13] Compiling tb/axi_master_bfm.sv...
xvlog -sv tb/axi_master_bfm.sv -work work
if errorlevel 1 goto error

echo [12/13] Compiling tb/virtual_ddr_model.sv...
xvlog -sv tb/virtual_ddr_model.sv -work work
if errorlevel 1 goto error

echo [13/13] Compiling tb/tb_full_system_verification.sv...
xvlog -sv tb/tb_full_system_verification.sv -work work
if errorlevel 1 goto error

echo [14/15] Compiling tb/tb_day14_complete.sv...
xvlog -sv tb/tb_day14_complete.sv -work work
if errorlevel 1 goto error

echo.
echo ========================================
echo Elaborating design...
echo ========================================
echo.

xelab -debug typical -relax -snapshot tb_day14_complete_behav work.tb_day14_complete -log elaborate.log
if errorlevel 1 goto error

echo.
echo ========================================
echo Running simulation...
echo ========================================
echo.

xsim tb_day14_complete_behav -runall -log simulate.log
if errorlevel 1 goto error

echo.
echo ========================================
echo Simulation completed successfully!
echo ========================================
echo.
echo Check simulate.log for results
echo Check tb_day14_complete.vcd for waveform analysis
echo.
pause
goto end

:error
echo.
echo ========================================
echo ERROR: Simulation failed!
echo ========================================
echo.
pause
exit /b 1

:end
exit /b 0
