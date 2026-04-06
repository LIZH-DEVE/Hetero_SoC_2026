AX7020 raw-copy soft-reset diagnostic image

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from raw_copy_dma_wrapper.xsa
2. fresh raw-copy bitstream extracted from that same XSA
3. raw-copy soft-reset diagnostic app ELF built against dedicated raw-copy standalone BSP

Expected board-side behavior:
- UART prints:
  RAWCOPY SOFT RESET DIAG
  RAWCOPY_SOFT_RESET_STAGE BEFORE_SOFT_RESET
  RAWCOPY_SOFT_RESET_STAGE AFTER_SOFT_RESET
  RAWCOPY_SOFT_RESET_OK
  RAWCOPY_SOFT_RESET_HEARTBEAT ...
