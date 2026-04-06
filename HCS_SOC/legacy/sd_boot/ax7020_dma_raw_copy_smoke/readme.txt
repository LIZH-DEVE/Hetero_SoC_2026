AX7020 Low-LUT Raw-Copy DMA Smoke

Purpose:
- Dedicated low-LUT board-smoke image for raw-copy DMA bring-up.
- Uses a fresh raw_copy_dma_wrapper XSA / FSBL / bitstream chain.

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from raw_copy_dma_wrapper.xsa
2. fresh raw_copy_dma_wrapper.bit extracted from that same XSA
3. raw-copy smoke application ELF

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
- App toolchain BSP root: same-platform zynq_fsbl_bsp if present, else explicit legacy fallback selected by build_ax7020_dma_raw_copy_smoke_app.ps1
- App ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_smoke_app\build\ax7020_dma_raw_copy_smoke_app.elf
- SHA256: 44B63D346F2AEB95973DB13476E7D8B00738E64D1C94D4040A62FA0AC86BD23B
- Timing summary:
  WNS = 7.28 ns
  TNS = 0 ns
  setup failing endpoints = 0
  WHS = 0.036 ns
  THS = 0 ns
  hold failing endpoints = 0

Board-proven rollback baseline:
- Current passing BOOT.BIN hash:
  44B63D346F2AEB95973DB13476E7D8B00738E64D1C94D4040A62FA0AC86BD23B

Previous root cause and permanent fix:
- Root cause:
  vendor PS configuration was re-applied during raw-copy XSA export and disabled S_AXI_HP0.
- Symptom:
  CSR access stayed alive, but descriptor fetch, DDR payload traffic, and CSW writeback could not complete.
- Permanent fix:
  export_raw_copy_dma_xsa.tcl must re-enable and reconnect S_AXI_HP0 after set_ps_config.

Expected board-side behavior:
- UART prints:
  DMA raw-copy smoke image
  RAWCOPY_STAGE INIT
  RAWCOPY_STAGE RESET
  RAWCOPY_STAGE SUBMIT
  RAWCOPY_STAGE WAIT_CSW
    CSW=0x40000000 owner=0 done=1 err=0 sts=0
  RAWCOPY_STAGE INVALIDATE_DST
  RAWCOPY_STAGE COMPARE
  DMA raw-copy smoke PASS

Phase 2 defaults frozen from this baseline:
- FCLK0 = 50MHz
- IRQ coalescing default = 8 completions or 5000 cycles (100us @ 50MHz)
- ring size minimum = 2 and software always keeps one slot open
- actual_len writeback and CSW writeback must complete after payload DDR write response before IRQ/completion is raised
