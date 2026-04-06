DMA gateway hybrid smoke image

Purpose:
- Release BOOT.BIN for the DMA gateway hybrid smoke path.
- Preserves the 3-stage boot structure: fsbl.elf, dma_gateway_hybrid_wrapper.bit, ax7020_dma_gateway_hybrid_smoke_app.elf.
- Expected UART pass criteria come from the existing hybrid smoke app and are frozen here for release validation.
- Current status:
  - board-proven Phase A hybrid gateway smoke image
  - current board-proven image hash:
    - C85DDC649E523FB03863CB2B9C842E434E173EE546BDB1FCADC56EB467507AD3
  - board evidence on 2026-03-28:
    - EXACT_FIT PASS
    - SHORT PASS
    - OVERFLOW PASS
    - WRONG_PORT PASS
    - UNALIGNED_REJECT PASS
    - DMA gateway hybrid smoke PASS

Expected UART pass criteria:
- DMA gateway hybrid smoke image
- EXACT_FIT PASS
- SHORT PASS
- OVERFLOW PASS
- WRONG_PORT PASS
- UNALIGNED_REJECT PASS
- DMA gateway hybrid smoke PASS

Build flow:
1. Run build_ax7020_dma_gateway_hybrid_smoke_app.ps1 to compile ax7020_dma_gateway_hybrid_smoke_app.elf.
2. Run build_ax7020_dma_gateway_hybrid_smoke_boot.ps1 to export dma_gateway_hybrid_wrapper.xsa, generate a standalone platform, and package BOOT.BIN.
3. Run deploy_ax7020_dma_gateway_hybrid_smoke_to_sd.ps1 to copy BOOT.BIN to the SD card.

Release directory contents after a successful boot build:
- BOOT.BIN
- boot.bif
- readme.txt
- fsbl.elf
- dma_gateway_hybrid_wrapper.bit
- ax7020_dma_gateway_hybrid_smoke_app.elf
