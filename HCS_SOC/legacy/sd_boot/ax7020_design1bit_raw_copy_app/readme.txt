AX7020 design1-bit + raw-copy-app Diagnostic

Purpose:
- Use the known-good repo design_1 FSBL + design_1 bitstream chain with the
  dedicated raw-copy smoke app.
- If this image prints RAWCOPY_STAGE markers, the raw-copy app/runtime is alive
  and the remaining blocker is in the dedicated raw-copy hardware/boot chain.

Clean boot image structure:
1. [bootloader] repo design_1 fresh fsbl.elf
2. repo design_1 fresh bitstream
3. raw-copy smoke application ELF

Source chain:
- Repo design_1 FSBL path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\repo_design1_uart_baseline_xsct\workspace\ax7020_repo_design1_uart_platform\zynq_fsbl\fsbl.elf
- Repo design_1 bitstream path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\design_1_wrapper.bit
- Raw-copy app ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_smoke_app\build\ax7020_dma_raw_copy_smoke_app.elf
- SHA256: 4CE01C4436534B08CD585709A82C1195BBC6649F61390AD498B9FD3E1DFE6CCC

Expected board-side behavior:
- UART should print at least:
  DMA raw-copy smoke image
  RAWCOPY_STAGE INIT
