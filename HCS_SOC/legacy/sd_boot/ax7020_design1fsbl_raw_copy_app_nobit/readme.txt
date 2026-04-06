AX7020 Design1-FSBL + Raw-Copy-App No-Bit Diagnostic

Purpose:
- Isolate raw-copy app/runtime by combining the known-good repo design_1 FSBL
  with the dedicated raw-copy smoke app.
- Omits the PL bitstream on purpose.

Clean boot image structure:
1. [bootloader] repo design_1 fresh fsbl.elf
2. raw-copy smoke application ELF

Source chain:
- Repo design_1 FSBL path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\repo_design1_uart_baseline_xsct\workspace\ax7020_repo_design1_uart_platform\zynq_fsbl\fsbl.elf
- Raw-copy app ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_smoke_app\build\ax7020_dma_raw_copy_smoke_app.elf
- SHA256: CB3938AF94CED98E805B834141AD66F200552D4F52B5FFB6A372352B5AF75A32

Expected board-side behavior:
- UART prints at least:
  RAWCOPY_STAGE INIT
