@echo off
call D:\Xilinx\Vivado\2024.1\settings64.bat
cd /d "D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\.codex_sim\raw_copy_reverify2"
xvlog -sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\inc\dma_csr_pkg.sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\core\axil_csr.sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\core\dma\dma_axis_fifo_wrapper.sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\core\dma\dma_raw_copy_engine.sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\core\dma\dma_desc_fetcher.sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\top\dma_raw_copy_subsystem.sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tb\tb_dma_raw_copy_engine.sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tb\tb_dma_raw_copy_subsystem.sv D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tb\tb_dma_desc_fetcher_doorbell_sanity.sv || exit /b 1
xelab tb_dma_raw_copy_engine -s tb_dma_raw_copy_engine_sim || exit /b 1
xsim tb_dma_raw_copy_engine_sim -runall || exit /b 1
xelab tb_dma_raw_copy_subsystem -s tb_dma_raw_copy_subsystem_sim || exit /b 1
xsim tb_dma_raw_copy_subsystem_sim -runall || exit /b 1
xelab tb_dma_desc_fetcher_doorbell_sanity -s tb_dma_desc_fetcher_doorbell_sanity_sim || exit /b 1
xsim tb_dma_desc_fetcher_doorbell_sanity_sim -runall || exit /b 1

