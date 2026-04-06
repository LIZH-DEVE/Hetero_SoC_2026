# Zero-Copy FastPath Feasibility Assessment

## Decision Summary

- Technical feasibility: `YES`
- Suitable as a small patch on the current release line: `NO`
- Recommended next step: `separate design stage and prototype branch`
- Recommended to preserve current baseline first: `YES`

## Current State

The current release baseline does not implement zero-copy `FastPath`.

What exists today is a `TXCAP-backed FastPath`:

- hit packets are captured into `TXCAP`
- hit/fallback counters are maintained
- no real external TX egress is driven from the active `FastPath` route

Relevant implementation evidence:

- `ctrl_fastpath_en` exists only on the shadow-inject control path:
  - [dma_gateway_hybrid_board_wrapper.v#L410](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/dma_gateway_hybrid_board_wrapper.v#L410)
- in the full control path, it is hard-disabled:
  - [dma_gateway_hybrid_board_wrapper.v#L433](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/dma_gateway_hybrid_board_wrapper.v#L433)
- current `FastPath` hit route is `FASTPATH_ROUTE_TXCAP`:
  - [dma_gateway_hybrid_board_wrapper.v#L773](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/dma_gateway_hybrid_board_wrapper.v#L773)
- `crypto_dma_subsystem` has a `tx_axis_*` output path:
  - [crypto_dma_subsystem.sv#L48](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/crypto_dma_subsystem.sv#L48)
- but the active wrapper throws it away and ties `tx_axis_tready` low:
  - [dma_gateway_hybrid_board_wrapper.v#L899](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/dma_gateway_hybrid_board_wrapper.v#L899)
  - [dma_gateway_hybrid_board_wrapper.v#L903](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/dma_gateway_hybrid_board_wrapper.v#L903)

## Why It Is Not A Small Change

Zero-copy `FastPath` is not "replace `TXCAP` with direct send".

It requires choosing and activating a real TX egress topology.

Three choices exist:

1. Reuse `crypto_dma_subsystem.tx_axis_*`
2. Reuse `network_stage1_path.o_tx_axis_*`
3. Build a new dedicated `FastPath` egress

Each option requires:

- active TX arbitration
- fallback arbitration against ACL / invalid frame / busy conditions
- replay of exact packet bytes without accidental modification
- real endpoint-ready flow control

This is a topology change, not a single-state change.

## Physical Risk

### Good news

- top-level resources still have headroom:
  - `Slice = 83.32%`
  - `BRAM Tile = 23.21%`

### Bad news

The live datapath region is already hot:

- `shadow_data_region Slice = 95.65%`
- `shadow_data_region BRAM Tile = 88.89%`

This means zero-copy `FastPath` is limited less by whole-chip totals and more by the existing floorplanned datapath region.

Any solution that adds new egress control, buffering, or arbitration in the same region risks:

- pblock overflow
- routing congestion regression
- timing regression

## Semantic Risk

Current validation already exposed mixed-state boundary issues:

- ACL-hit traffic can still receive a delayed `LIVE_AES` reply
- `FastPath-hit + AES-1472 + ACL-hit` tri-mix triggers `shadow compare fail`

Reference:

- [2026-04-06_shadow_mirror_matrix_and_trimix_validation.md](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/2026-04-06_shadow_mirror_matrix_and_trimix_validation.md)
- [board_uart_trimix_20260406_111657.txt](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/board_uart_trimix_20260406_111657.txt)

That means zero-copy work would not begin from a semantically perfect `FastPath` baseline.

It would begin from a baseline where mixed-state interactions are already known to be imperfect.

## Best Technical Entry Point

If zero-copy `FastPath` is pursued, the best starting point is:

### Preferred direction

- reuse `crypto_dma_subsystem.tx_axis_*`

### Reason

- the path already exists
- `loopback_mode == 2'b10` already drives it:
  - [crypto_dma_subsystem.sv#L293](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/crypto_dma_subsystem.sv#L293)
- `bridge_tx_rd_en` already supports readout against `tx_axis_tready`:
  - [crypto_dma_subsystem.sv#L483](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/crypto_dma_subsystem.sv#L483)

### But still required

- wrapper-level TX wiring
- explicit mode selection between:
  - DMA writeback
  - TXCAP evidence path
  - zero-copy TX egress
- validation rewrite for `FastPath` acceptance

## Recommendation

### Recommended

- preserve current baseline as immutable
- treat zero-copy `FastPath` as a new prototype effort
- start with a design doc and isolated branch
- keep `TXCAP` available as debug/fallback evidence during the prototype

### Not recommended

- do not implement it directly on the current release line
- do not remove `TXCAP` first
- do not start before resolving current tri-mix semantic issues

## Final Judgment

Zero-copy `FastPath` is one of the few remaining FPGA-side features that still looks worth pursuing.

But under the current resource map and validation state, it should be treated as:

- `feasible`
- `high risk`
- `prototype-only`

It should not be framed as an incremental cleanup item.
