AX7020 raw-copy wait-csw diagnostic image

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from raw_copy_dma_wrapper.xsa
2. fresh raw-copy bitstream extracted from that same XSA
3. raw-copy wait-csw diagnostic app ELF built against dedicated raw-copy standalone BSP

Expected board-side behavior:
- UART prints:
  RAWCOPY WAIT CSW DIAG
  RAWCOPY_WAIT_CSW_STAGE BEFORE_WAIT
  RAWCOPY_WAIT_CSW_STAGE AFTER_WAIT rc=...
  RAWCOPY_WAIT_CSW_OK
  RAWCOPY_WAIT_CSW_HEARTBEAT ...
