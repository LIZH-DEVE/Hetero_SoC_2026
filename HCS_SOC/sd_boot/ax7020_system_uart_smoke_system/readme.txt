AX7020 system_wrapper UART Smoke Image

Contents:
- BOOT.BIN = FSBL + system_wrapper.bit + ax7020_system_uart_smoke_app.elf

Board-side scope:
1. UART-only smoke
2. No DMA CSR access
3. Used to separate boot/UART/bitstream issues from DMA MMIO issues
