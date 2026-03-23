# Robeieda Porting Notes

## Purpose
- This note defines what should be preserved when moving the current non-DMA control-plane baseline to `robeieda`.
- The goal is to let the transport or hardware-adaptation layer change later without breaking the external contract.

## Non-negotiable oracle
- Python host-side scripts are the single source of truth for protocol behavior.
- If `robeieda` output differs from Python Golden Vectors, assume the board implementation is wrong.
- Do not alter host-side Python scripts to fit `robeieda` during migration.
- Only a deliberate protocol revision may update both sides together.

## Three-layer split
### 1. Protocol layer
- Must remain identical between platforms.
- Stable items:
  - `4660 = AES ECB`
  - `4661 = SM4`
  - `4662 = control`
  - 24-byte control header
  - message IDs
  - status codes
  - STATUS field order
  - BENCH payload format

### 2. Session and security-control layer
- Preferred to reuse directly on `robeieda`.
- Stable logic:
  - source-IP-scoped session
  - `HELLO -> session_id`
  - `SET_KEY -> authorized_algos`
  - `session_id + seq_id` replay window
  - auth-failure threshold
  - replay-failure threshold
  - lock/unlock state machine
  - zero keys on lock

### 3. Hardware-adaptation layer
- Replaceable.
- Current implementation uses:
  - direct MMIO crypto execution
  - current AX7020 queue and reply path
  - placeholder binding ID source
- Later DMA migration may replace this layer without changing the first two layers.

## What must stay stable later
- External port meanings
- Control header layout
- `HELLO / SET_KEY / LOCK / UNLOCK / STATUS / BENCH`
- `STATUS` payload order
- `BENCH` record format
- Data-plane length rule
- Data-plane requirement that source IP must be authorized first

## What can be replaced later
- `gateway_get_device_binding_id()`
  - currently returns constant `0x41583702`
  - later may read real DNA or platform-specific binding ID
- direct-MMIO encrypt path
  - later may become DMA or another adapter
- FNV-based key derivation and auth-tag internals
  - may be replaced if host and board are updated together
- software-only lock implementation
  - may later become stronger tamper response

## Minimum porting checklist for teammate
1. Independent bring-up stage: `UDP 4662 echo`, no parser, no session logic.
2. Parse the fixed 24-byte control header and print decoded fields.
3. Implement `HELLO -> session_id` with hard-coded `binding_id = 0x41583702`.
4. Recreate session table keyed by source IP.
5. Keep `session_id` issuance semantics.
6. Keep 32-entry replay window behavior.
7. Keep lock and unlock semantics.
8. Keep exported counters and field order.
9. Recreate authorization gate in front of data plane.
10. Preserve raw ECB block data on `4660/4661`.
11. Preserve `BENCH` response structure even if internal benchmark code changes.

## Dependency graph
- `UDP Echo -> Header Parser -> HELLO -> SET_KEY -> Replay -> Lock/Unlock -> Data Plane -> BENCH`
- Do not skip ahead in this graph.
- If a stage is broken, fix that stage before enabling the next one.

## Functions that are safe to stub first
- binding-ID source:
  - keep a constant until real hardware identity exists
- benchmark backend:
  - may return valid structure with temporary internal timing source
- lightweight self-destruct backend:
  - keep software lock and key zeroing first

## Functions that should not be stubbed if protocol compatibility matters
- control header parser/packer
- status-code mapping
- replay-window update logic
- session lookup by source IP
- `SET_KEY` authorization mask update
- unauthorized data-plane drop

## Migration risk notes
- Do not move replay fields into data packets.
- Do not add payload headers to `4660/4661`.
- Do not change `binding_id` endianness in auth-tag computation.
- Do not change `STATUS` field order without updating host scripts at the same time.
- Do not silently widen accepted data-plane lengths beyond `1472` on one side only.
