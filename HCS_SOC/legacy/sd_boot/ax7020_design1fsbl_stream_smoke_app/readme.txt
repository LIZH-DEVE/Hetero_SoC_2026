AX7020 design1-FSBL + stream-smoke-app Diagnostic

Purpose:
- Temporary board-proven Phase 3 baseline for stream-mode DMA.
- Uses the known-good repo design_1 FSBL with the dedicated stream-smoke bitstream
  and the dedicated stream-smoke app.
- This image currently proves that stream-smoke app + bitstream + data path are valid on hardware,
  while the dedicated stream-smoke FSBL remains the only unresolved with-bit blocker.

Clean boot image structure:
1. [bootloader] known-good repo design_1 fsbl.elf
2. dedicated stream_smoke_dma_wrapper.bit
3. dedicated stream-smoke app ELF

Source chain:
- design_1 FSBL: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_design1fsbl_stream_smoke_app\fsbl.elf
- stream-smoke bitstream: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_design1fsbl_stream_smoke_app\stream_smoke_dma_wrapper.bit
- stream-smoke app ELF: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\sd_boot\ax7020_design1fsbl_stream_smoke_app\ax7020_dma_raw_copy_stream_smoke_app.elf
- SHA256: 8F137D1A03F093A49FC6BCFB98EABDB5060687CC18CB8CC6F0FA664215D8D9CA

Expected board-side behavior:
- UART prints:
  DMA stream smoke image
  STREAM_STAGE EXACT_FIT PASS actual_len=1024
  STREAM_STAGE SHORT PASS actual_len=64
  STREAM_STAGE OVERFLOW PASS actual_len=64
  DMA stream smoke PASS
