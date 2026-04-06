# system_wrapper Timing Gate

This file defines the required timing workflow for the `system_wrapper` DMA line.

## Rule

Do not treat `system_wrapper` as board-eligible until routed timing is clean:

- `WNS >= 0`
- `TNS = 0`
- setup failing endpoints = `0`
- hold failing endpoints = `0`

The timing gate is enforced by:

- `HCS_SOC\invoke_vivado_timing_triage.ps1`
- `HCS_SOC\read_vivado_timing_summary.ps1`
- `HCS_SOC\build_ax7020_dma_mvp_smoke_fresh.ps1`
- `HCS_SOC\deploy_ax7020_dma_mvp_smoke_to_sd.ps1`

## Required triage order

Do not start by rewriting RTL. First inspect the routed DCP and classify the failure:

1. `report_timing_summary`
2. `report_timing -max_paths 10 -sort_by group -input_pins -routable_nets`
3. `report_design_analysis -timing -logic_level_distribution`
4. `report_high_fanout_nets -timing -load_types -max_nets 50`
5. `report_clock_interaction`
6. `report_utilization`
7. `report_utilization -hierarchical -hierarchical_depth 4`

Generated reports are written under:

- `HCS_SOC\timing_triage\system_wrapper_current\`

The utilization reports are required because `system_wrapper` is area-constrained. Do not
accept a timing fix that only works by materially increasing LUT pressure unless the reports
show the design still has safe placement headroom.

For the full-top BRAM migration path, do not force `ram_style = block` onto async-read
memories. The LUTRAM-heavy blocks must first be refactored to synchronous read interfaces
so the added latency is explicit and the storage can then be moved to BRAM without
creating a timing paradox.

## Current routed facts

From the current routed `system_wrapper` DCP:

- `WNS = -1.521ns`
- `TNS = -989.432ns`
- setup failing endpoints = `1107`
- `WHS = +0.043ns`
- hold failing endpoints = `0`

The current failure signature is:

- dominant synchronous path group:
  - `clk_fpga_0 -> clk_fpga_0`
- worst-path logic depth:
  - approximately `24` logic levels
- worst-path location:
  - `u_network_stage1`
  - `u_tx_stack`
  - `txcap_data_mem_reg[*]`
- worst-path structure:
  - mixed logic delay and route delay, not a broad multi-clock collapse

The high-fanout report also shows very large reset fanout in `u_crypto_bridge`, but that is not the top violating path in the current routed design.

The current area signature is also relevant:

- `Slice LUTs = 39107 / 53200` (`73.51%`)
- `Slice = 13275 / 13300` (`99.81%`)
- `LUT as Memory = 12750 / 17400` (`73.28%`)

That means timing fixes must be area-aware. Broad register insertion is not an acceptable
default strategy because slice pressure is already near the device limit.

The current hierarchical hotspots are:

- `u_crypto_bridge`
  - `18165` LUTs
  - mostly logic, not LUTRAM
- `u_network_stage1`
  - `9292` LUTs
  - `5632` LUTRAMs
- `u_acl_filter`
  - `4771` LUTs
  - `4160` LUTRAMs
- `u_pbm`
  - `3525` LUTs
  - `2816` LUTRAMs
- `u_net_pbm`
  - `7025` LUTs
  - `5632` LUTRAMs

By contrast, the actual DMA control blocks are small:

- `u_dma_engine = 215 LUTs`
- `u_fetcher = 55 LUTs`
- `u_s2mm_mm2s = 53 LUTs`

This means "use DMA to reduce LUT" is only valid if DMA replaces larger fabric datapaths.
Adding more DMA-side logic on top of the current system is unlikely to help area. The first
area-reduction targets should be LUTRAM-heavy packet buffers and optional board-smoke-only
logic, not the DMA engine itself.

## Allowed fixes

Only choose a fix after the triage reports identify the dominant failure mode.

If the reports show deep logic:

- insert a pipeline register at the specific hot stage
- prefer surgical cuts in:
  - AXI address/control preparation
  - PBM egress datapath
  - `u_network_stage1/u_tx_stack`

If the reports show high fanout:

- add explicit fanout control such as:
  - `(* max_fanout = "32" *)`
- prefer register replication over broad functional rewrites

If the reports show slice pressure dominated by distributed memory:

- prefer moving packet buffers or capture storage from LUTRAM toward BRAM
- first refactor those memories to synchronous read semantics
- prefer reducing duplicated shallow memories before adding new datapath registers
- treat any LUT-heavy fix as suspect until `utilization_hier.rpt` confirms the extra cost is small
- prefer board-smoke top variants that bypass nonessential fabric blocks instead of adding more logic to an already LUT-bound top

This applies directly to:

- `u_pbm`
- `u_net_pbm`
- `u_acl_filter/u_acl`

Do not attempt BRAM migration before the read-side contract is synchronous.

If the reports show real CDC pressure:

- fix the crossing explicitly
- or constrain the path correctly with:
  - `set_false_path`
  - or `set_max_delay -datapath_only`

If the reports show tool-placement pressure after logic cleanup:

- enable stronger implementation optimization:
  - `phys_opt_design`
  - `Explore`
  - `AggressiveExplore`

## Disallowed shortcuts

Do not:

- deploy DMA smoke to SD when timing is failing
- reuse stale `fsbl.elf`
- treat a successful `write_bitstream` as timing closure
- blindly refactor state machines before triage
- blindly add pipeline stages when slice usage is already near full
- use board behavior to guess timing root cause when routed reports already exist
