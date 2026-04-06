AX7020 raw-copy includes diagnostic image

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from raw_copy_dma_wrapper.xsa
2. fresh raw-copy bitstream extracted from that same XSA
3. raw-copy includes diagnostic app ELF built against dedicated raw-copy standalone BSP

Expected board-side behavior:
- UART prints:
  RAWCOPY INCLUDES DIAG
  RAWCOPY_INCLUDE_HEADERS_OK
  RAWCOPY_INCLUDE_HEARTBEAT ...
