# Zero-Copy FastPath Egress Design

Date: `2026-04-06`  
Branch: `codex/zero-copy-fastpath-prototype`

## 1. Purpose

This document defines the prototype design for a true zero-copy `FastPath` egress on top of the current `udp_gateway_shadow_mirror_wrapper` active path.

This is an experimental design. It does not change the frozen `final-release` baseline. The stable rollback point remains:

- branch: `final-release`
- tag: `baseline-shadow-mirror-20260406-af4e1bd`

## 2. Problem Statement

The current active baseline does not implement zero-copy `FastPath`.

What exists today:

- `FastPath` hit detection
- hit / fallback accounting
- `TXCAP` evidence storage

What does not exist today:

- a real external `tx_axis_*` egress driven by `FastPath`

In the active wrapper, the internal `crypto_dma_subsystem.tx_axis_*` path is discarded and `tx_axis_tready` is tied low. Therefore, `FastPath` hit packets never leave through a real AXI-Stream transmit path.

## 3. Scope

This prototype is limited to one objective:

- turn `FastPath` hit packets into real `tx_axis_*` egress traffic

This prototype intentionally does not solve:

- true `CBC`
- full `NIC` datapath
- optimized DMA
- dual-core enablement
- semantic cleanup of all existing tri-mix edge cases

## 4. Chosen Approach

Chosen approach:

- add real top-level `tx_axis_*` egress ports to `dma_gateway_hybrid_board_wrapper`
- reuse `crypto_dma_subsystem.tx_axis_*` as the zero-copy egress source
- make `FastPath` hit traffic take this egress path directly
- keep non-hit traffic on the existing `Crypto -> DMA -> DDR` route
- remove `TXCAP` from the `FastPath` hit mainline for this prototype

Rejected alternatives:

1. Keep `TXCAP` as the main hit path and add zero-copy as a side path  
   Rejected because it does not prove true zero-copy egress.

2. Route through `network_stage1_path.o_tx_axis_*`  
   Rejected because it drags inactive stage1/NIC semantics into the prototype.

3. Build a brand-new dedicated egress path  
   Rejected for the prototype because the existing `crypto_dma_subsystem.tx_axis_*` path already provides a better starting point.

## 5. Architectural Boundaries

### 5.1 Active Area

The prototype is centered on:

- `rtl/top/dma_gateway_hybrid_board_wrapper.v`
- `rtl/top/crypto_dma_subsystem.sv`

### 5.2 Control Scope

The prototype remains scoped to the current `FastPath` control domain. It does not introduce a new software-visible mode model beyond what is necessary to activate the egress path.

### 5.3 Release Isolation

This design must not be merged into `final-release` until it passes:

- fresh synthesis
- fresh implementation
- routed congestion review
- routed timing review
- board-level smoke validation

## 6. Dataflow

### 6.1 Current Behavior

Current hit flow:

1. frame enters shadow inject path
2. ACL filter runs
3. `FastPath` header parser classifies hit
4. route becomes `FASTPATH_ROUTE_TXCAP`
5. payload is captured into `TXCAP`
6. no real transmit egress occurs

### 6.2 Prototype Behavior

Prototype hit flow:

1. frame enters shadow inject path
2. ACL filter runs
3. `FastPath` header parser classifies hit
4. hit frame is forwarded into the existing `crypto_dma_subsystem` pass-through egress path
5. wrapper exports the resulting `tx_axis_*` stream through new top-level ports
6. non-hit traffic remains on the existing DMA writeback path

## 7. Interface Changes

## 7.1 Wrapper Top-Level

Add new top-level outputs to `dma_gateway_hybrid_board_wrapper`:

- `o_tx_axis_tdata[31:0]`
- `o_tx_axis_tvalid`
- `o_tx_axis_tlast`
- `o_tx_axis_tkeep[3:0]`
- `i_tx_axis_tready`

These ports become the real physical egress for prototype zero-copy `FastPath`.

## 7.2 Internal Wiring

Replace the current discarded connection:

- `tx_axis_tdata()`
- `tx_axis_tvalid()`
- `tx_axis_tlast()`
- `tx_axis_tkeep()`
- `tx_axis_tready(1'b0)`

with real wrapper-level signals and top-level port export.

## 8. Backpressure Model

Backpressure handling is mandatory. No packet is allowed to be silently dropped because downstream egress stalls.

### 8.1 Required Behavior

If `i_tx_axis_tready` deasserts:

- `crypto_dma_subsystem` must stall transmit progression
- the wrapper must stop draining hit traffic into the zero-copy egress
- upstream `aclf_tready` and then `stage1_inject_tready` must reflect that stall

### 8.2 Intended Mechanism

The prototype relies on the existing `crypto_dma_subsystem` pass-through behavior:

- `bridge_tx_rd_en = tx_axis_tready && !crypto_to_dma_empty` in pass-through mode

That means downstream backpressure can naturally stop reads from the crypto bridge. The wrapper work is to ensure the hit-route state machine does not consume more frame data than the downstream egress can accept.

### 8.3 Acceptance Rule

No zero-copy hit path is accepted unless AXI-Stream backpressure is preserved end-to-end:

- egress `tready` low
- internal transmit read enable low
- wrapper ingress ready low

## 9. Arbitration Rules

The prototype uses a strict priority model:

1. `FastPath` hit traffic owns the transmit egress
2. non-hit traffic does not transmit externally and continues to DDR writeback
3. `ACL` drop traffic must not enter zero-copy egress

This prototype does not attempt to multiplex multiple external egress classes. It only proves the hit-path can leave through a real AXI-Stream port.

## 10. State Machine Impact

The current `FASTPATH_ROUTE_TXCAP` state is no longer sufficient for the hit path.

Prototype change:

- introduce a dedicated egress route state for hit traffic, or repurpose the existing hit route into a real TX route

The route state must not declare completion until:

- all words of the hit frame have been accepted by downstream egress
- the final beat with `tlast` has handshaken

## 11. Verification Plan

### 11.1 Pre-Board Verification

Required:

- targeted unit and contract tests for new wrapper ports and route behavior
- synthesis
- implementation
- routed congestion report review
- post-route timing review

### 11.2 Physical Audit Gates

Required review items:

- no new routed DRC blocker
- no new methodology DRC blocker
- post-route `WNS` remains non-negative
- congestion must be explicitly inspected after routing

### 11.3 Board Audit Gates

Required board checks:

- hit traffic emits real `tx_axis_*`
- non-hit traffic still reaches DDR writeback path
- ACL-hit traffic does not leak into zero-copy egress
- no immediate regression in `board_check`, `ACL`, `security`, or `performance`

## 12. Risks

Primary risks:

1. `shadow_data_region` is already hot
   - high chance of placement or routing regression

2. Existing tri-mix semantics are already imperfect
   - `ACL-hit` can still produce delayed reply behavior
   - `shadow compare fail` has already been observed under mixed stress

3. Wrapper-level top interface change may require downstream integration updates
   - block design or export flow may need refresh

## 13. Success Criteria

This prototype is successful only if all of the following are true:

- real top-level `tx_axis_*` egress exists
- `FastPath` hit frames leave through that egress
- downstream backpressure propagates correctly
- routed implementation remains physically closed
- baseline rollback remains untouched on `final-release`

## 14. Non-Success Conditions

The prototype is not considered successful if any of these occurs:

- hit frames still only land in `TXCAP`
- egress stalls cause silent frame loss
- implementation closes only with negative timing
- congestion becomes visibly severe and unstable
- the prototype breaks baseline rollback discipline

