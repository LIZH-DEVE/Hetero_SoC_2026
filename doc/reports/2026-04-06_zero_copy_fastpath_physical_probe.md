# 2026-04-06 Zero-Copy FastPath Physical Probe

## Scope

This report captures the outcome of the experimental `zero-copy fastpath egress` probe on branch `codex/zero-copy-fastpath-prototype`.

The probe goal was narrow:

- expose a real `tx_axis_*` egress from the active wrapper
- route fastpath-hit traffic to that egress instead of `TXCAP`
- propagate external `tready` back into the hit-route state machine
- measure whether the design still routes and meets timing

This report does **not** claim board-usable zero-copy transmission.

## Experiment Checkpoint

- branch: `codex/zero-copy-fastpath-prototype`
- commit: `1717cde`
- stable baseline preserved on branch `final-release`
- stable baseline tag: `baseline-shadow-mirror-20260406-af4e1bd`

## RTL Probe Result

The prototype did implement wrapper-level zero-copy egress control:

- `FASTPATH_ROUTE_EGRESS_REPLAY`
- `FASTPATH_ROUTE_EGRESS_DMA`
- wrapper-level mux from `egress_tx_axis_*` vs `subsys_tx_axis_*`
- direct use of `i_tx_axis_tready` for hit-route backpressure

Primary file:

- `/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/dma_gateway_hybrid_board_wrapper.v`

## Physical Result

### Routed Implementation

Implementation completed through route.

- no congestion windows above level 5
- post-route timing remained positive

Evidence:

- congestion report:
  - `/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/archive/triage/zero_copy_fastpath_step2_congestion.rpt`
- timing report:
  - `/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_timing_summary_routed.rpt`

Key timing numbers:

- `WNS = 2.480ns`
- `WHS = 0.010ns`

### Bitstream Blocker

Bitstream generation did not complete because the new top-level ports are unconstrained:

- `i_tx_axis_tready`
- `o_tx_axis_tdata[31:0]`
- `o_tx_axis_tkeep[3:0]`
- `o_tx_axis_tlast`
- `o_tx_axis_tvalid`

Routed DRC evidence:

- `/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_drc_routed.rpt`

Blocking checks:

- `NSTD-1`
- `UCIO-1`

## Deeper Architectural Blocker

The unconstrained ports are not the real problem. They only expose a deeper topology issue:

the active design has **no real PL egress sink** for this new `tx_axis_*` path.

### Evidence 1: Ethernet is PS MIO, not PL EMIO

From the active block design:

- `PCW_ENET0_ENET0_IO = MIO 16 .. 27`
- `PCW_ENET0_GRP_MDIO_IO = MIO 52 .. 53`
- `PCW_EN_EMIO_ENET0 = 0`
- `PCW_EN_EMIO_ENET1 = 0`

Source:

- `/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.srcs/sources_1/bd/udp_gateway_shadow_mirror/udp_gateway_shadow_mirror.bd`

This means the board Ethernet path is owned by PS MIO. The current PL design does not have an enabled EMIO Ethernet escape path.

### Evidence 2: Existing `network_stage1_path` TX is also discarded

The wrapper still instantiates `network_stage1_path`, but:

- external RX is hard-wired to zero
- its `o_tx_axis_*` outputs are captured into unused wires

Source:

- `/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/dma_gateway_hybrid_board_wrapper.v`

This means there is no active on-board PL transmit consumer already waiting for a fastpath stream.

### Evidence 3: No PL MAC / AXI Ethernet datapath in active BD

The active block design does not expose evidence of:

- `axi_ethernet`
- `tri_mode`
- `temac`
- `gmii_to_rgmii`

So the new wrapper `tx_axis_*` ports currently terminate at the top level with no physically defined destination.

## Engineering Conclusion

This probe proved one narrow but useful fact:

- wrapper-level zero-copy fastpath control logic can still route
- congestion remained below the critical threshold
- timing stayed positive after route

But it also established a hard boundary:

- **true board-usable PL zero-copy fastpath egress is not available in the current active topology**

The current design can therefore support only one honest statement:

- the control logic for zero-copy egress is physically probeable
- the board topology does not currently provide a valid PL transmit sink for it

## Options From Here

### Option A: Stop at Physical Probe

Treat this experiment as complete proof that the wrapper-level egress control path can route and meet timing.

Best when:

- the goal is architectural evidence
- the release baseline must remain intact

### Option B: Redesign the Board/BD Egress Topology

Introduce a real PL transmit destination, for example:

- a PL MAC path
- a deliberate EMIO-based redesign if hardware permits
- another board-valid downstream consumer

This is a real architectural change, not a small patch.

### Option C: Retarget to an Internal Sink

Retarget the zero-copy stream to:

- ILA
- debug sink
- internal capture FIFO

This would allow more verification, but it would no longer be honest to call it board egress.

## Recommendation

Do not continue adding RTL blindly on top of this prototype.

The next decision is architectural:

- either accept this branch as a successful physical probe
- or redesign the egress topology before claiming any usable zero-copy transmit path
