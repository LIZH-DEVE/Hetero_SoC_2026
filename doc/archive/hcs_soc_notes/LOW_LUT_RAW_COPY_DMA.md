# Low-LUT Raw-Copy DMA Contract

This document fixes the board contract for the first low-area DMA smoke path.

## Scope

The first raw-copy board-smoke variant is:

- `MM2S -> AXIS FIFO -> S2MM`
- no network path
- no ACL path
- no crypto bridge
- no PBM / net PBM path

The goal is to keep the DMA datapath small while preserving a real software-visible
descriptor and CSW flow.

## FIFO contract

The MM2S-to-S2MM elastic buffer must be an AXIS FIFO configured with:

- BRAM storage
- depth 512
- `TDATA`
- `TVALID/TREADY`
- `TLAST` enabled with 1-bit width

The FIFO must preserve `TLAST` end to end. The final beat from MM2S must assert
`TLAST`, the FIFO must pass it through unchanged, and S2MM must use it as part of
its completion condition.

The first raw-copy board image is invalid if the FIFO drops `TLAST`, because S2MM
can remain busy indefinitely and CSW write-back never becomes architecturally visible.

## PS-side alignment contract

The smoke app must enforce cache-line and buffer alignment explicitly:

- `src_buffer` aligned to 32B
- `dst_buffer` aligned to 32B
- descriptor storage separated from destination data
- transfer length a multiple of 32B

The app must invalidate the destination range only after CSW completion:

1. submit descriptor
2. flush descriptor and source payload
3. `dsb()`
4. write `sw_tail`
5. `dsb()`
6. write `doorbell`
7. poll CSW until completion
8. `invalidate(dst)` via `Xil_DCacheInvalidateRange(dst_addr, len)`
9. `dsb()`
10. `memcmp(src, dst, len)`

The destination invalidate is mandatory because the Cortex-A9 cache operates on
cache lines, not byte ranges.

## Reset contract

The AXIS FIFO must be tied into the same reset domain as the raw-copy DMA path.
Software soft reset must also clear the FIFO so that stale data from an aborted
transaction cannot leak into the next copy.

Required behavior:

- global reset clears the FIFO
- software soft reset clears the FIFO
- the next transaction must start with an empty FIFO
- CSW must reflect only the post-reset transaction

## Low-LUT boundary

The first board-eligible raw-copy variant keeps only:

- `u_fetcher`
- `u_dma_engine`
- `u_s2mm_mm2s`
- CSR
- AXIS FIFO
- required PS / DDR interfaces

It excludes:

- `u_network_stage1`
- `u_acl_filter`
- `u_crypto_bridge`
- `u_pbm`
- `u_net_pbm`

This is the board-smoke path for restoring a controllable DMA baseline.

## Verification rule

The raw-copy smoke is not board-eligible unless all of the following are true:

- TLAST is preserved through the FIFO
- destination buffers are 32B aligned
- transfer length is a 32B multiple
- `invalidate(dst)` happens only after CSW completion
- soft reset clears the FIFO before the next transfer
