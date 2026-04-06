AX7020 stream-smoke-bit + design1-UART Diagnostic

Purpose:
- Use a known-good design_1 FSBL + known-good design_1 UART app with the
  dedicated stream-smoke bitstream.
- If this image stays silent, the stream-smoke bitstream itself is sufficient
  to break board bring-up.

Clean boot image structure:
1. [bootloader] known-good repo design_1 fsbl.elf
2. dedicated stream_smoke_dma_wrapper.bit
3. known-good repo design_1 UART baseline app ELF

Source chain:
- Stream-smoke XSA: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\stream_smoke_dma_wrapper.xsa
- Stream-smoke bitstream: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_streamsmokebit_design1_uart\stream_smoke_dma_wrapper.bit
- design_1 FSBL: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_streamsmokebit_design1_uart\fsbl.elf
- design_1 UART app ELF: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_streamsmokebit_design1_uart\ax7020_repo_design1_uart_baseline_app.elf
- SHA256: 47F2AAF3D7FCF53DFB466FEDEA51155BEA496E80B3754773EEFB21EDCAA0200C

Expected board-side behavior:
- UART should print at least:
  REPO DESIGN1 UART BASELINE
