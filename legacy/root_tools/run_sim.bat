@echo off
setlocal

:: 1. Set Path
set VIVADO_BIN=D:\Xilinx\Vivado\2024.1\bin
set PATH=%VIVADO_BIN%;%PATH%

:: 2. Setup Directories
set PROJ_DIR=D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026
set SIM_DIR=%PROJ_DIR%\sim_output
if not exist "%SIM_DIR%" mkdir "%SIM_DIR%"
cd /d "%SIM_DIR%"

echo [INFO] Cleaning up previous runs...
if exist xsim.dir rmdir /s /q xsim.dir
if exist *.log del *.log
if exist *.pb del *.pb
if exist *.jou del *.jou

echo [INFO] Compiling Design Sources...

:: Utils
call xvlog -sv "%PROJ_DIR%/rtl/inc/sync_fifo.sv"
call xvlog -sv "%PROJ_DIR%/rtl/core/gearbox_128_to_32.sv"

:: Crypto Core (Verilog files)
:: We compile all .v files in crypto directory to ensure dependencies like aes_sbox etc are met
for %%f in ("%PROJ_DIR%\rtl\core\crypto\*.v") do call xvlog "%%f"

:: Crypto Bridge (SystemVerilog)
call xvlog -sv "%PROJ_DIR%/rtl/core/crypto/crypto_bridge_top.sv"

:: Security
call xvlog -sv "%PROJ_DIR%/rtl/security/key_vault.sv"
call xvlog -sv "%PROJ_DIR%/rtl/security/config_packet_auth.sv"
call xvlog -sv "%PROJ_DIR%/rtl/security/acl_match_engine.sv"
call xvlog -sv "%PROJ_DIR%/rtl/security/acl_packet_filter.sv"

:: DMA & System
call xvlog -sv "%PROJ_DIR%/rtl/core/axil_csr.sv"
call xvlog -sv "%PROJ_DIR%/rtl/core/dma/dma_master_engine.sv"
call xvlog -sv "%PROJ_DIR%/rtl/core/dma/dma_s2mm_mm2s_engine.sv"
call xvlog -sv "%PROJ_DIR%/rtl/core/dma/dma_desc_fetcher.sv"
call xvlog -sv "%PROJ_DIR%/rtl/core/pbm/pbm_controller.sv"
call xvlog -sv "%PROJ_DIR%/rtl/top/dma_subsystem.sv"

:: Testbench
call xvlog -sv "%PROJ_DIR%/tb/tests/tb_dma_system.sv"

echo [INFO] Elaborating...
call xelab -debug typical -top tb_dma_system -snapshot tb_dma_system_snap -timescale 1ns/1ps

echo [INFO] Simulating...
call xsim tb_dma_system_snap -R > simulation_run2.log
echo [INFO] Simulation Finished.
echo [INFO] Searching for performance results in simulation_run2.log...
echo ------------------------------------------------------------
findstr /I /C:"Throughput" /C:"Elapsed Time" /C:"Sim Cycles" /C:"Crypto Time" /C:"Performance Results" simulation_run2.log
echo ------------------------------------------------------------
echo [INFO] Full log available at: %SIM_DIR%\simulation_run2.log

endlocal
