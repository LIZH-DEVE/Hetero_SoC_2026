AX7020 Raw-Copy Hybrid No-Bit Diagnostic

Purpose:
- Isolate raw-copy FSBL/app handoff by combining the dedicated raw-copy FSBL
  with the known-good repo design_1 UART baseline application.
- Omits the PL bitstream on purpose.

Clean boot image structure:
1. [bootloader] raw-copy fresh fsbl.elf
2. repo design_1 UART baseline application ELF

Source chain:
- Raw-copy FSBL path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_dma_raw_copy_smoke\fsbl.elf
- Repo design_1 baseline app ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_repo_design1_uart_baseline_app\build\ax7020_repo_design1_uart_baseline_app.elf
- SHA256: 612850B9B1E5D64F38BD0DAC73F138BA826FC398FC990A25D452153E4D33542E

Expected board-side behavior:
- UART prints:
  REPO DESIGN1 UART BASELINE
  UART1 OK
  FRESH_XSA_FSBL_CHAIN
  REPO_HEARTBEAT N
