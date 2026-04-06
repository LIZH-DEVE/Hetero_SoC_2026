AX7020 raw-copy static-regions diagnostic image

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from raw_copy_dma_wrapper.xsa
2. fresh raw-copy bitstream extracted from that same XSA
3. raw-copy static-regions diagnostic app ELF built against dedicated raw-copy standalone BSP

Expected board-side behavior:
- UART prints:
  RAWCOPY STATIC REGIONS DIAG
  RAWCOPY_STATIC_REGIONS_OK
  RAWCOPY_STATIC_HEARTBEAT ...
