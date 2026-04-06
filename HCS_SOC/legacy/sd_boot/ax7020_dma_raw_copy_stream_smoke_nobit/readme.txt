AX7020 Stream Smoke DMA (No-Bit Diagnostic)

Purpose:
- Diagnostic image to separate stream-smoke bitstream/PL failures from FSBL/app bring-up.
- Uses the same fresh stream-smoke FSBL and the same stream-smoke app.
- Omits the PL bitstream on purpose.

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from stream_smoke_dma_wrapper.xsa
2. stream-smoke application ELF

Fresh source chain:
- XSA path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\stream_smoke_dma_wrapper.xsa
- XSCT workspace: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_platform_xsct\workspace
- Platform name: ax7020_dma_stream_smoke_platform
- FSBL path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_platform_xsct\workspace\ax7020_dma_stream_smoke_platform\zynq_fsbl\fsbl.elf
- App API BSP root: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_platform_xsct\workspace\ax7020_dma_stream_smoke_platform\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0
- App ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_stream_smoke_app\build\ax7020_dma_raw_copy_stream_smoke_app.elf
- SHA256: E0A8C93200A203162CC96D118CAA9E2EA36A005D7E61257BBC6CD951595C0A44

Expected board-side behavior:
- UART prints at least:
  DMA stream smoke image
