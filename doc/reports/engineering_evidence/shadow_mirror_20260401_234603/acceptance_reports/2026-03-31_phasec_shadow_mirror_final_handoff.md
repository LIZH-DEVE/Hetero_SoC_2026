# Phase C Shadow Mirror Final Handoff

Date:
- `2026-04-01`

Scope:
- Final closeout for `ax7020_udp_gateway_shadow_mirror`
- Includes Stage 2 SG proof result, final full-image merge-back result, security closure, and JTAG soak closure

## Final Status

- Phase C functional path: PASS
- Stage 2 SG proof: PASS
- Full `shadow_mirror` merge-back on `xc7z020`: PASS
- ACL board check: PASS
- Replay / lock / re-auth security board check: PASS
- Shadow fastpath board check: PASS
- Board performance acceptance: PASS
- `30` minute JTAG soak: PASS
- Final acceptance state: `board-proven + performance-proven + security-proven + soak-proven`

## Final Acceptance Image

- Image: `HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror/BOOT.BIN`
- SHA256: `F41015670B925DC863D2F53A66E965F3AB37C0DE8CC1FFE867B71BCD7CD45B26`

## Final Board Performance Capture

- Capture directory: `doc/reports/board_benchmarks/shadow_mirror_20260401_191044`
- JSON: `board_bench_report.json`
- Markdown: `board_bench_summary.md`

Average speedup versus same-board PS software baseline:
- AES: `2.726501x`
- SM4: `2.055588x`

Per-length highlights:
- AES `16 B` to `1472 B`: all rows `> 1.0x`
- SM4 `16 B` to `1472 B`: all rows `> 1.0x`

## Security Acceptance Evidence

ACL closure:
- Blocked shadow ingress traffic increments `acl_drop_count`
- Board observation: `acl_drop_count 0 -> 1`

Replay / lock / re-auth closure:
- replay attempts are rejected and counted
- lock clears authorization
- locked state suppresses data-plane replies
- re-authentication restores service

Shadow fastpath closure:
- `FASTPATH_HIT_COUNT=2`
- `FASTPATH_FALLBACK_COUNT=0`
- TXCAP evidence captured on board

## JTAG Soak Result

- Capture directory: `doc/reports/board_soak/shadow_mirror_20260401_224117`
- JSON: `soak_report.json`
- Markdown: `soak_summary.md`
- Mode: `mixed soak`
- Duration: `30` minutes
- Cycle interval: `15` seconds
- Cycles completed: `128`
- AES probes: `128`
- SM4 probes: `128`
- ACL probes: `12`
- Replay probes: `6`
- Final soak result: `PASS`

Observed soak invariants:
- `locked=0` throughout
- `authorized_mask=3` throughout
- `bind_fail=0`
- `crypto_timeout=0`
- `crypto_fail=0`
- `drop_replay 0 -> 6`
- every ACL micro-probe produced `acl_delta=1`

Important boundary:
- under JTAG soak, UART capture remained supplemental
- the final `30` minute run passed without a UART file being created
- this was treated as a warning, not a functional failure

## Stage 2 Proof Result

- Proof capture directory: `doc/reports/board_benchmarks/hybrid_perf_proof_20260331_181431`
- Result:
  - AES avg speedup = `4.877192x`
  - SM4 avg speedup = `2.847728x`
- Proof conclusion:
  - descriptor-driven SG batch DMA/crypto path is valid on board
  - single-launch descriptor batching with `1000` repeats is sufficient to amortize launch overhead

## Merge-Back Result

- The validated descriptor-driven DMA batch executor was merged back into `shadow_mirror` BENCH
- Functional live/shadow behavior remained intact
- Performance gate remained:
  - `avg_speedup >= 1.0x` per algorithm
- Final full-image board run passed that gate on `xc7z020`

## Hardware Slimming Required For Fit

The full merge-back only became implementable after reducing hardware footprint:
- `CRYPTO_NUM_INSTANCES: 2 -> 1`
- `DMA_RAW_COPY_FIFO_DEPTH: 512 -> 32`
- `udp_gateway_shadow_inject_path INJ_DEPTH: 512 -> 32`
- `crypto_bridge_top mid_fifo: 64 -> 16`
- `crypto_bridge_top out_fifo: 128 -> 16`

Important boundary:
- `shadow_inject_path` was retained
- capacity was reduced, not removed
- fail-open behavior remains acceptable when the inject path is busy

## Post-Slimming Implementation Snapshot

Placed utilization from `udp_gateway_shadow_mirror_wrapper_utilization_placed.rpt`:
- Slice LUTs: `25736 / 53200 = 48.38%`
- Slice Registers: `30299 / 106400 = 28.48%`
- Slice usage: `12419 / 13300 = 93.38%`
- Block RAM Tile: `0.36%`

Interpretation:
- The original blocker was not BRAM exhaustion
- The actual issue was LUT/FF density and slice packing pressure
- Slimming the hybrid DMA and crypto-side buffering was enough to restore full implementation

## Acceptance Evidence

Functional UART / control evidence:
- `UDP crypto gateway started @ ports 4660(AES) 4661(SM4) 4662(CTRL)`
- `LIVE_CTRL PASS`

Security evidence:
- ACL counter increments on blocked traffic
- replay is rejected without driving the system into full destructive self-lock during soak

Performance evidence:
- `Target result: PASS`
- AES avg speedup `2.726501x`
- SM4 avg speedup `2.055588x`

Soak evidence:
- `SOAK_RESULT=PASS`
- `cycles_completed=128`

## Residual Non-Blockers

- BSP warning: `XUartPs_IsTransmitEmpty` macro redefinition
- App warning: `gateway_hw_encrypt_buffer_sync` unused in the final shadow build
- JTAG soak UART capture can be absent; current soak flow treats UART as supplemental unless explicit hard-bad strings are observed

These did not block build, implementation, boot, board acceptance, or long-run soak acceptance.

## Recommended Final Statement

Recommended project status wording:
- `Phase C corrected combined shadow_mirror image is local-verified, board-proven, performance-proven, security-proven, and soak-proven on xc7z020`
- `Descriptor-driven DMA batch BENCH path is merged back into the final shadow_mirror image`
