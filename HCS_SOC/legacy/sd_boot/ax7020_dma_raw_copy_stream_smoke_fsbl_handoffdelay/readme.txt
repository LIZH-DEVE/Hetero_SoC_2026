AX7020 Stream-Smoke FSBL Diagnostic (handoffdelay)

Purpose:
- Dedicated stream-smoke FSBL handoffdelay image for minimal-perturbation root-cause isolation.
- Uses the dedicated stream-smoke FSBL, dedicated stream-smoke bitstream, and dedicated stream-smoke app.
- Adds two fixed delay-spin perturbations in the with-bit handoff path and emits no new UART breadcrumbs.
- Delay points are after ps7_post_config() and before FsblHookBeforeHandoff().

Expected board-side diagnostic markers:
- No new FSBL_DIAG breadcrumbs are expected from the FSBL.
- Board pass is judged only by the stream-smoke app UART log.

Clean boot image structure:
1. [bootloader] patched dedicated stream-smoke fsbl.elf
2. stream_smoke_dma_wrapper.bit
3. ax7020_dma_raw_copy_stream_smoke_app.elf

Source chain:
- XSA path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\stream_smoke_dma_wrapper.xsa
- XSCT workspace: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_fsbl_handoffdelay_xsct\workspace
- Platform name: ax7020_dma_stream_smoke_platform
- Patched FSBL path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_fsbl_handoffdelay_xsct\workspace\ax7020_dma_stream_smoke_platform\zynq_fsbl\fsbl.elf
- App API BSP root: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_stream_smoke_fsbl_handoffdelay_xsct\workspace\ax7020_dma_stream_smoke_platform\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0
- App ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_stream_smoke_app\build\ax7020_dma_raw_copy_stream_smoke_app.elf
- SHA256: 9CD676A321ED85A885F478332B1D388ECE8F1052C2235353EF75E1982C9340D2

Current policy:
- official dedicated stream-smoke image remains experimental
- temporary board-proven Phase 3 baseline remains ax7020_design1fsbl_stream_smoke_app
