AX7020 raw-copy submit diagnostic image

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from raw_copy_dma_wrapper.xsa
2. fresh raw-copy bitstream extracted from that same XSA
3. raw-copy submit diagnostic app ELF built against dedicated raw-copy standalone BSP

Expected board-side behavior:
- UART prints:
  RAWCOPY SUBMIT DIAG
  RAWCOPY_SUBMIT_STAGE BEFORE_SUBMIT
  RAWCOPY_SUBMIT_STAGE AFTER_SUBMIT rc=...
  RAWCOPY_SUBMIT_OK
  RAWCOPY_SUBMIT_HEARTBEAT ...
