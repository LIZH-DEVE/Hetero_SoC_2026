AX7020 raw-copy invalidate/compare diagnostic image

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from raw_copy_dma_wrapper.xsa
2. fresh raw-copy bitstream extracted from that same XSA
3. raw-copy invalidate/compare diagnostic app ELF built against dedicated raw-copy standalone BSP

Expected board-side behavior:
- UART prints:
  RAWCOPY INVALIDATE COMPARE DIAG
  RAWCOPY_INVALIDATE_COMPARE_STAGE WAIT_DONE
  RAWCOPY_INVALIDATE_COMPARE_STAGE BEFORE_INVALIDATE
  RAWCOPY_INVALIDATE_COMPARE_STAGE AFTER_COMPARE match=...
  RAWCOPY_INVALIDATE_COMPARE_OK
  RAWCOPY_INVALIDATE_COMPARE_HEARTBEAT ...
