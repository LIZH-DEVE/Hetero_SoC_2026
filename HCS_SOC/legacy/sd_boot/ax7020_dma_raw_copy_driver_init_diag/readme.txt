AX7020 raw-copy driver-init diagnostic image

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from raw_copy_dma_wrapper.xsa
2. fresh raw-copy bitstream extracted from that same XSA
3. raw-copy driver-init diagnostic app ELF built against dedicated raw-copy standalone BSP

Expected board-side behavior:
- UART prints:
  RAWCOPY DRIVER INIT DIAG
  RAWCOPY_DRIVER_INIT_OK
  RAWCOPY_DRIVER_HEARTBEAT ...
