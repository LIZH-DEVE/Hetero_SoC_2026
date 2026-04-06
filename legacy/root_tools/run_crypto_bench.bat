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

:: Testbench (Package first)
call xvlog -sv "%PROJ_DIR%/tb/tests/crypto_vectors_pkg.sv"
call xvlog -sv "%PROJ_DIR%/tb/tests/tb_dma_subsystem_crypto_encdec.sv"

echo [INFO] Elaborating...
call xelab -debug typical -top tb_dma_subsystem_crypto_encdec -snapshot tb_crypto_snap -timescale 1ns/1ps

echo [INFO] Simulating...
call xsim tb_crypto_snap -R > crypto_run.log

echo [INFO] Extracting Test Results...
findstr /C:"[TEST " crypto_run.log

endlocal
