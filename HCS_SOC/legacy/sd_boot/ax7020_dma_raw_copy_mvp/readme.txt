AX7020 Low-LUT Raw-Copy DMA MVP

Purpose:
- Dedicated low-LUT board-smoke image for Phase 2 fixed-mode DMA MVP.
- Validates 3 successful descriptors, 4th submit returns -5, and IRQ coalescing count/timeout paths.
- 3 descriptors staged while hardware is quiesced.
- 4th staged submit returns -5 before the doorbell is rung.
- Explicit ring/doorbell release then starts hardware consumption.

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from raw_copy_dma_wrapper.xsa
2. fresh raw_copy_dma_wrapper.bit extracted from that same XSA
3. raw-copy MVP application ELF

Fresh source chain:
- Vivado project: HCS_SOC.xpr
- XSA export script: export_raw_copy_dma_xsa.ps1 / export_raw_copy_dma_xsa.tcl
- XSA path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\raw_copy_dma_wrapper.xsa
- XSA extract dir: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_platform_xsct\xsa_extract
- Bitstream path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_platform_xsct\xsa_extract\raw_copy_dma_wrapper.bit
- XSCT workspace: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_platform_xsct\workspace
- Platform name: ax7020_dma_raw_copy_platform
- FSBL path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_platform_xsct\workspace\ax7020_dma_raw_copy_platform\zynq_fsbl\fsbl.elf
- App API BSP root: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_platform_xsct\workspace\ax7020_dma_raw_copy_platform\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0
- App ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_mvp_app\build\ax7020_dma_raw_copy_mvp_app.elf
- SHA256: DCBDE852FDCDC1E90C99E9C13A89687896A9337385EED0C54116B9B860A13654
- Timing summary:
  WNS = 5.998 ns
  TNS = 0 ns
  setup failing endpoints = 0
  WHS = 0.02 ns
  THS = 0 ns
  hold failing endpoints = 0

Expected board-side behavior:
- UART prints:
  DMA raw-copy MVP image
  MVP_STAGE RING_FULL_CHECK submit rc[3]=-5
  MVP_IRQ_CONFIG count=2 timeout=64 cycles
  MVP_IRQ_COUNT status=0x...
  MVP_IRQ_TIMEOUT status=0x...
  DMA raw-copy MVP PASS
