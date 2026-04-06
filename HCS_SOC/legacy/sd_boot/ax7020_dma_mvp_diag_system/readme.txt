AX7020 DMA MVP Diagnostic Image

Contents:
- BOOT.BIN = FSBL + system_wrapper.bit + ax7020_dma_mvp_diag_app.elf

Board-side scope:
1. UART banner before any PL MMIO
2. Stage markers around ring init, key program, inject enable
3. Normal and error DMA smoke transactions after stage markers
