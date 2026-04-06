AX7020 Stream-Smoke FSBL Diagnostic (trace)

Purpose:
- Dedicated stream-smoke FSBL trace image for with-bit root-cause isolation.
- Uses the dedicated stream-smoke FSBL, dedicated stream-smoke bitstream, and dedicated stream-smoke app.
- Adds post-ps7_init UART breadcrumbs only. First trusted breadcrumb is AFTER_PS7_INIT.
- No ENTER_MAIN breadcrumb is emitted.

Expected board-side diagnostic markers:
- FSBL_DIAG AFTER_PS7_INIT
- FSBL_DIAG BEFORE_PCAP_LOAD
- FSBL_DIAG AFTER_PCAP_LOAD
- FSBL_DIAG BEFORE_POST_CONFIG
- FSBL_DIAG AFTER_POST_CONFIG
- FSBL_DIAG BEFORE_HANDOFF

Clean boot image structure:
1. [bootloader] patched dedicated stream-smoke fsbl.elf
2. stream_smoke_dma_wrapper.bit
3. ax7020_dma_raw_copy_stream_smoke_app.elf

Source chain:
- XSA path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\stream_smoke_dma_wrapper.xsa
- XSCT workspace: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_fsbl_trace_xsct\workspace
- Platform name: ax7020_dma_stream_smoke_platform
- Patched FSBL path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_fsbl_trace_xsct\workspace\ax7020_dma_stream_smoke_platform\zynq_fsbl\fsbl.elf
- App API BSP root: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_fsbl_trace_xsct\workspace\ax7020_dma_stream_smoke_platform\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0
- App ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_stream_smoke_app\build\ax7020_dma_raw_copy_stream_smoke_app.elf
- SHA256: 2F0B6B21E5810E499AE323F6307C1BA8CD0DE4D968749EDF6DBB7C20232EC02F

Current policy:
- official dedicated stream-smoke image remains experimental
- temporary board-proven Phase 3 baseline remains ax7020_design1fsbl_stream_smoke_app
