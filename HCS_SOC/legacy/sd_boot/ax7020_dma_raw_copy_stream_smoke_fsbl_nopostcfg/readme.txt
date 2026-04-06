AX7020 Stream-Smoke FSBL Diagnostic (nopostcfg)

Purpose:
- Dedicated stream-smoke FSBL no-post-config image for with-bit root-cause isolation.
- Uses the dedicated stream-smoke FSBL, dedicated stream-smoke bitstream, and dedicated stream-smoke app.
- Skips ps7_post_config() only on the with-bit path while preserving the rest of handoff flow.
- First trusted breadcrumb is AFTER_PS7_INIT. No ENTER_MAIN breadcrumb is emitted.

Expected board-side diagnostic markers:
- FSBL_DIAG AFTER_PS7_INIT
- FSBL_DIAG BEFORE_PCAP_LOAD
- FSBL_DIAG AFTER_PCAP_LOAD
- FSBL_DIAG BEFORE_POST_CONFIG
- FSBL_DIAG AFTER_POST_CONFIG
- FSBL_DIAG BEFORE_HANDOFF

If the stream-smoke app reaches:
- DMA stream smoke PASS
then the remaining blocker is concentrated in the dedicated FSBL post-config / with-bit handoff window.

Clean boot image structure:
1. [bootloader] patched dedicated stream-smoke fsbl.elf
2. stream_smoke_dma_wrapper.bit
3. ax7020_dma_raw_copy_stream_smoke_app.elf

Source chain:
- XSA path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\stream_smoke_dma_wrapper.xsa
- XSCT workspace: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_fsbl_nopostcfg_xsct\workspace
- Platform name: ax7020_dma_stream_smoke_platform
- Patched FSBL path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_fsbl_nopostcfg_xsct\workspace\ax7020_dma_stream_smoke_platform\zynq_fsbl\fsbl.elf
- App API BSP root: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_fsbl_nopostcfg_xsct\workspace\ax7020_dma_stream_smoke_platform\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0
- App ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_stream_smoke_app\build\ax7020_dma_raw_copy_stream_smoke_app.elf
- SHA256: 45100B7194DD808E52EB66BC2A631A65C99C2BF82C41C66E16AC9F26B9C4CD48

Current policy:
- official dedicated stream-smoke image remains experimental
- temporary board-proven Phase 3 baseline remains ax7020_design1fsbl_stream_smoke_app
