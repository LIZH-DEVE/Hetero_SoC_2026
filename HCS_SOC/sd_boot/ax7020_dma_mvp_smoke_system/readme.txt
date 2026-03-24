AX7020 DMA MVP Smoke Image

Contents:
- BOOT.BIN = FSBL + system_wrapper.bit + ax7020_dma_mvp_smoke_app.elf

Board-side scope:
1. UART banner and DMA CSR snapshot
2. One normal descriptor via PS CSR injector -> PBM -> Crypto -> DMA -> CSW
3. One error descriptor returning CSW ERR + STS

This image does not include:
- UDP gateway
- control plane ports 4660/4661/4662
- real DNA binding
- strengthened self-destruct
