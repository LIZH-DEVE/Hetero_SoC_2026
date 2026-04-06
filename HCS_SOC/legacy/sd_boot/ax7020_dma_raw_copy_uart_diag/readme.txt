AX7020 raw-copy UART-only diagnostic image

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from raw_copy_dma_wrapper.xsa
2. fresh raw-copy bitstream extracted from that same XSA
3. UART-only diagnostic app ELF built against dedicated raw-copy standalone BSP

Fresh source chain:
- XSA: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\raw_copy_dma_wrapper.xsa
- Workspace: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_platform_xsct\workspace
- Platform BSP root: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_platform_xsct\workspace\standalone_bsp\ps7_cortexa9_0
- FSBL: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_platform_xsct\workspace\ax7020_dma_raw_copy_platform\zynq_fsbl\fsbl.elf
- Bitstream: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_dma_raw_copy_uart_diag\xsa_extract\raw_copy_dma_wrapper.bit
- App ELF: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_uart_diag_app\build\ax7020_dma_raw_copy_uart_diag_app.elf
- SHA256: 59405C239B095EA72537ED9F903CD96CDB96E1BDAAB58EE108EB9492422D0F5B

Expected board-side behavior:
- UART prints:
  RAWCOPY UART DIAG
  RAWCOPY_PLATFORM_OK
  RAWCOPY_UART_HEARTBEAT ...
