UDP gateway shadow mirror image

Purpose:
- Phase C shadow mirror app for the combined live direct crypto + hybrid DMA shadow hardware line.
- Confirms live gateway control flow remains intact.
- Confirms the PS mirror shadow path uses deep-copy payload isolation and sticky halt on timeout.
- This is not a live cutover image.

Expected UART pass criteria:
- LIVE_CTRL PASS
- LIVE_AES PASS
- LIVE_SM4 PASS
- SHADOW_AES PASS
- SHADOW_SM4 PASS
- SHADOW_INVALID_SKIP PASS
- UDP gateway shadow mirror PASS

Sticky Halt contract:
- Shadow DMA poll timeout enters HALTED.
- HALTED is sticky.
- Shadow submit stays best-effort and must fail-open to live.
- SHADOW_TIMEOUT_HALT PASS is a local/contract-only diagnostic, not a normal board-pass requirement.

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from udp_gateway_shadow_mirror_wrapper.xsa
2. fresh udp_gateway_shadow_mirror_wrapper.bit extracted from that same XSA
3. ax7020_udp_gateway_shadow_mirror_app.elf

Fresh source chain:
- Vivado project: HCS_SOC.xpr
- XSA path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\udp_gateway_shadow_mirror_wrapper.xsa
- XSA extract dir: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_udp_gateway_shadow_mirror_platform_xsct\xsa_extract
- Bitstream path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_udp_gateway_shadow_mirror\udp_gateway_shadow_mirror_wrapper.bit
- XSCT workspace: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_udp_gateway_shadow_mirror_platform_xsct\workspace
- Platform name: ax7020_udp_gateway_shadow_mirror_platform
- FSBL path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_udp_gateway_shadow_mirror\fsbl.elf
- App API BSP root: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_udp_gateway_shadow_mirror_platform_xsct\workspace\ax7020_udp_gateway_shadow_mirror_platform\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0
- App ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_udp_gateway_shadow_mirror\ax7020_udp_gateway_shadow_mirror_app.elf
- SHA256: 360860625831D0E912CD18F92528B4840738773EB30C9C857B17F203295E4AB0

Current status:
- Shadow First
- PS Mirror
- Sticky Halt
- Combined live direct crypto + hybrid DMA shadow hardware line.
- Board-proven hybrid smoke hash: C85DDC649E523FB03863CB2B9C842E434E173EE546BDB1FCADC56EB467507AD3
- Wrong-port and unaligned contracts remain hardware-enforced

Board performance capture:
- Output artifacts: board_bench_report.json, board_bench_summary.md
- BENCH capture is control-plane only.
- Required UART evidence for BENCH mode:
  UDP crypto gateway started @ ports 4660(AES) 4661(SM4) 4662(CTRL)
  LIVE_CTRL PASS
- Short payload rows 16B/32B may remain below 1.0x; acceptance is based on average speedup.
