AX7020 Stream-Smoke FSBL Diagnostic (handofflite)

Purpose:
- Dedicated stream-smoke FSBL handofflite image for minimal-perturbation root-cause isolation.
- Uses the dedicated stream-smoke FSBL, dedicated stream-smoke bitstream, and dedicated stream-smoke app.
- Keeps only the handoff-window UART breadcrumbs inside FsblHandoff().
- Intentionally omits AFTER_PS7_INIT / BEFORE_PCAP_LOAD / AFTER_PCAP_LOAD.

Expected board-side diagnostic markers:
- FSBL_DIAG BEFORE_POST_CONFIG
- FSBL_DIAG AFTER_POST_CONFIG
- FSBL_DIAG BEFORE_HANDOFF

Clean boot image structure:
1. [bootloader] patched dedicated stream-smoke fsbl.elf
2. stream_smoke_dma_wrapper.bit
3. ax7020_dma_raw_copy_stream_smoke_app.elf

Source chain:
- XSA path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\stream_smoke_dma_wrapper.xsa
- XSCT workspace: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_fsbl_handofflite_xsct\workspace
- Platform name: ax7020_dma_stream_smoke_platform
- Patched FSBL path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_fsbl_handofflite_xsct\workspace\ax7020_dma_stream_smoke_platform\zynq_fsbl\fsbl.elf
- App API BSP root: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_fsbl_handofflite_xsct\workspace\ax7020_dma_stream_smoke_platform\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0
- App ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_stream_smoke_app\build\ax7020_dma_raw_copy_stream_smoke_app.elf
- SHA256: 47618AC72551B33EDD9C22839817A20F23F5B4B6B4E2B66E9D2B64CE39E5C3C6

Current policy:
- official dedicated stream-smoke image remains experimental
- temporary board-proven Phase 3 baseline remains ax7020_design1fsbl_stream_smoke_app
