AX7020 raw-copy reinit-after-reset diagnostic image

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from raw_copy_dma_wrapper.xsa
2. fresh raw-copy bitstream extracted from that same XSA
3. raw-copy reinit-after-reset diagnostic app ELF built against dedicated raw-copy standalone BSP

Expected board-side behavior:
- UART prints:
  RAWCOPY REINIT AFTER RESET DIAG
  RAWCOPY_REINIT_AFTER_RESET_STAGE BEFORE_REINIT
  RAWCOPY_REINIT_AFTER_RESET_STAGE AFTER_REINIT
  RAWCOPY_REINIT_AFTER_RESET_OK
  RAWCOPY_REINIT_HEARTBEAT ...
