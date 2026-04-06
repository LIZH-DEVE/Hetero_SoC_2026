AX7020 Repo design_1 UART Baseline (No-Bit Diagnostic)

Purpose:
- Control image to verify whether repo-generated no-bit boot images can
  reach the known-good design_1 UART baseline application without PL load.

Clean boot image structure:
1. [bootloader] repo design_1 fresh fsbl.elf
2. repo design_1 UART baseline application ELF

Source chain:
- Repo design_1 FSBL path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\repo_design1_uart_baseline_xsct\workspace\ax7020_repo_design1_uart_platform\zynq_fsbl\fsbl.elf
- Repo design_1 baseline app ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_repo_design1_uart_baseline_app\build\ax7020_repo_design1_uart_baseline_app.elf
- SHA256: 612850B9B1E5D64F38BD0DAC73F138BA826FC398FC990A25D452153E4D33542E

Expected board-side behavior:
- UART prints:
  REPO DESIGN1 UART BASELINE
  UART1 OK
  FRESH_XSA_FSBL_CHAIN
  REPO_HEARTBEAT N
