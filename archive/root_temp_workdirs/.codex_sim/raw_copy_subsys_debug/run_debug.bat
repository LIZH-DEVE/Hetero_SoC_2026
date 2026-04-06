@echo off
call D:\Xilinx\Vivado\2024.1\settings64.bat
cd /d D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\.codex_sim\raw_copy_subsys_debug
xvlog -sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\inc\dma_csr_pkg.sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\core\axil_csr.sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\core\dma\axis_packet_fifo_bram.sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\core\dma\dma_axis_fifo_wrapper.sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\core\dma\dma_raw_copy_engine.sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\core\dma\dma_desc_fetcher.sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\top\dma_raw_copy_subsystem.sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tb\tb_dma_raw_copy_subsystem.sv || exit /b 1
xelab --timescale 1ns/1ps --debug typical -mt off -log xelab_tb_raw_copy_subsystem.log tb_dma_raw_copy_subsystem -s tb_dma_raw_copy_subsystem_sim
exit /b %ERRORLEVEL%
