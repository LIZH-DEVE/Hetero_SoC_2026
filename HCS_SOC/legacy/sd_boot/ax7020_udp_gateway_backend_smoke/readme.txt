UDP gateway backend smoke image

Purpose:
- Phase B backend split smoke image for the hybrid ingress line.
- Confirms the direct MMIO backend regression still passes.
- Confirms the DMA probe backend smoke path still passes on the board-proven hybrid wrapper.
- This is not a live cutover image.
- The smoke path is smoke-only and does not bind live UDP ports.

Expected UART pass criteria:
- DIRECT_BACKEND PASS
- DMA_PROBE EXACT_FIT PASS
- DMA_PROBE SHORT PASS
- DMA_PROBE OVERFLOW PASS
- DMA_PROBE WRONG_PORT PASS
- DMA_PROBE UNALIGNED_REJECT PASS
- DMA_PROBE PASS
- UDP gateway backend smoke PASS

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from dma_gateway_hybrid_wrapper.xsa
2. fresh dma_gateway_hybrid_wrapper.bit extracted from that same XSA
3. ax7020_udp_gateway_backend_smoke_app.elf

Fresh source chain:
- Vivado project: HCS_SOC.xpr
- XSA path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\dma_gateway_hybrid_wrapper.xsa
- XSA extract dir: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_gateway_hybrid_platform_xsct\xsa_extract
- Bitstream path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_udp_gateway_backend_smoke\dma_gateway_hybrid_wrapper.bit
- XSCT workspace: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_gateway_hybrid_platform_xsct\workspace
- Platform name: ax7020_dma_gateway_hybrid_platform
- FSBL path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_udp_gateway_backend_smoke\fsbl.elf
- App API BSP root: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_gateway_hybrid_platform_xsct\workspace\ax7020_dma_gateway_hybrid_platform\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0
- App ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_udp_gateway_backend_smoke\ax7020_udp_gateway_backend_smoke_app.elf
- SHA256: 28093643E0B5E8AF74BA0317D09F54638FCE82D490E80D24E26883FC191E8007

Current status:
- Phase B backend split smoke image
- Reuse the board-proven hybrid hardware line
- Board-proven hybrid smoke hash: C85DDC649E523FB03863CB2B9C842E434E173EE546BDB1FCADC56EB467507AD3
- Wrong-port and unaligned contracts remain hardware-enforced
