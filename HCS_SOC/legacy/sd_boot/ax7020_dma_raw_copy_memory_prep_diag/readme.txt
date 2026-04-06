AX7020 raw-copy memory-prep diagnostic image

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from raw_copy_dma_wrapper.xsa
2. fresh raw-copy bitstream extracted from that same XSA
3. raw-copy memory-prep diagnostic app ELF built against dedicated raw-copy standalone BSP

Expected board-side behavior:
- UART prints:
  RAWCOPY MEMORY PREP DIAG
  RAWCOPY_MEMORY_PREP_OK
  RAWCOPY_MEMORY_HEARTBEAT ...
