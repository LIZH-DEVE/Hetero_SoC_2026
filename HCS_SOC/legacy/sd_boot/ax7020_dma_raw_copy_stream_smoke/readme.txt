AX7020 Stream Smoke DMA

Purpose:
- Dedicated Phase 3 stream-smoke image for stream-mode DMA.
- Current status: experimental dedicated with-bit path kept for FSBL root-cause work.
- This is not the current board-proven Phase 3 baseline.
- Uses a delay-only dedicated FSBL stabilization in the with-bit handoff window.
- Validates EXACT_FIT, SHORT, and OVERFLOW / missing TLAST handling using a stream dummy source block.
- word-granular only in this phase: packet lengths are restricted to 4-byte multiples.
- No IRQ path is used in this smoke line.

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from stream_smoke_dma_wrapper.xsa
2. fresh stream_smoke_dma_wrapper.bit extracted from that same XSA
3. stream-smoke application ELF

Fresh source chain:
- Vivado project: HCS_SOC.xpr
- XSA path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\stream_smoke_dma_wrapper.xsa
- XSA extract dir: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_platform_xsct\xsa_extract
- Bitstream path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_platform_xsct\xsa_extract\stream_smoke_dma_wrapper.bit
- XSCT workspace: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_platform_xsct\workspace
- Platform name: ax7020_dma_stream_smoke_platform
- FSBL path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_platform_xsct\workspace\ax7020_dma_stream_smoke_platform\zynq_fsbl\fsbl.elf
- FSBL stabilization: delay-only, two fixed spins in FsblHandoff() with-bit path
- App API BSP root: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_platform_xsct\workspace\ax7020_dma_stream_smoke_platform\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0
- App ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_stream_smoke_app\build\ax7020_dma_raw_copy_stream_smoke_app.elf
- SHA256: 91EDCE39C4198167C54192A7520DA63C17B097170EAED6D1478C1A90B200EEFA
- Timing summary:
  WNS = 5.886 ns
  TNS = 0 ns
  setup failing endpoints = 0
  WHS = 0.027 ns
  THS = 0 ns
  hold failing endpoints = 0

Current board validation policy:
- dedicated stream-smoke with-bit path is still blocked by the dedicated stream-smoke FSBL
- use the temporary board-proven baseline for Phase 3 board validation:
  design1 fsbl.elf + stream_smoke_dma_wrapper.bit + ax7020_dma_raw_copy_stream_smoke_app.elf
- do not promote this image until it passes 3 consecutive cold boots

Expected UART pass criteria:
- DMA stream smoke image
- STREAM_STAGE EXACT_FIT PASS actual_len=1024
- STREAM_STAGE SHORT PASS actual_len=64
- STREAM_STAGE OVERFLOW PASS actual_len=64
- DMA stream smoke PASS
