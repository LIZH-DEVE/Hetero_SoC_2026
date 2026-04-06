# 2026-04-06 Shadow Mirror Defense Assets

## Executive Position

- Current release baseline is defensible for:
  - `AES` hardware datapath
  - `SM4` hardware datapath
  - `ACL` countered blocking behavior
  - `TXCAP-backed FastPath`
  - `Security` replay/lock/reauth flow
  - `18`-scenario host benchmark matrix
- Current release baseline is not defensible for:
  - "ACL-hit always implies no reply"
  - "FastPath + active AES + ACL-hit tri-mix is fully clean"
  - `12h` burn-in under tri-mix state churn

## Fixed Claims For Thesis / Defense

### Claim 1: Heterogeneous storage topology reconstruction

Use:

- Historical hotspot: `LUT as Memory = 10056`
- Current top-level placed value: `267 / 17400 = 1.53%`

Suggested wording:

> Rather than treating timing failure as a pure logic problem, the design restructured on-chip storage topology around explicit XPM-backed memories. This removed distributed-RAM routing hotspots and reopened routing capacity on an XC7Z020 fabric under severe placement pressure.

### Claim 2: PPA-constrained architecture tradeoff

Use:

- `shadow_data_region Slice = 10407 / 10944 = 95.65%`
- `WNS = 4.561ns`
- matrix baseline:
  - AES `2.774736x`
  - SM4 `2.105868x`

Suggested wording:

> Under a floorplanned data region already driven to 95.65% Slice occupancy, the system deliberately rejected a full NIC datapath and 256-beat DMA expansion. The resulting host-offload partition preserved a 4.561ns timing moat while sustaining a repeatable 2.7x-class acceleration baseline on real hardware.

### Claim 3: CBC physical isolation

Use:

- [2026-04-05-shadow-mirror-cbc-readiness.md](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/superpowers/plans/2026-04-05-shadow-mirror-cbc-readiness.md)

Suggested wording:

> CBC was not merged performatively into a block-oriented fast path. The project stopped at Phase 1 readiness, preserving packet metadata continuity and packet-atomic state capture while explicitly isolating XOR/chaining work until a packet-aware transport contract can support it without destroying throughput claims.

## Matrix Result Summary

Primary artifact:

- [bench_matrix_summary.md](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/board_bench_matrix/shadow_mirror_20260406_110058/bench_matrix_summary.md)

Hard numbers:

- `18` scenarios complete
- all scenarios `200 / 200`
- `0` timeout
- `0` mismatch
- mixed `AES/SM4` alternating load covered at:
  - `64B`
  - `512B`
  - `1472B`
  - `ACL off`
  - `ACL on(non-matching rule)`

What this supports:

- The current active mainline is stable for:
  - pure `AES`
  - pure `SM4`
  - alternating `AES/SM4`

## Tri-Mix Risk Boundary

Primary artifact:

- [2026-04-06_shadow_mirror_matrix_and_trimix_validation.md](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/2026-04-06_shadow_mirror_matrix_and_trimix_validation.md)
- [board_uart_trimix_20260406_111657.txt](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/board_uart_trimix_20260406_111657.txt)

Confirmed issues:

1. `ACL` counter increments, but blocked traffic can still receive a delayed `LIVE_AES` reply.
2. `FastPath-hit + AES-1472 + ACL-hit` tri-mix triggers `shadow compare fail` on the `1472B` AES leg.

Defense-safe phrasing:

> The system is stable under the validated benchmark matrix, but aggressive tri-mix state-switch stress exposed two boundary issues: ACL semantics remain counter-valid but not yet end-to-end silent, and the shadow-compare path is not yet clean under 64B fastpath plus 1472B active-path plus ACL-hit interleave.

## Allowed And Forbidden Claims

### Allowed

- "The 18-scenario benchmark matrix passed on real hardware."
- "The active AES/SM4 datapath is stable under pure and alternating mixed load."
- "Current FastPath validation proves TXCAP-backed fastpath hit behavior."
- "CBC is isolated at readiness stage rather than merged prematurely."

### Forbidden

- "ACL-hit traffic is fully suppressed end-to-end."
- "Tri-mix state churn is bug-free."
- "The design survived a 12-hour mixed-state burn-in."

## Suggested Slide Skeleton

### Slide 1: System Position

- Active topology
- what is physically closed
- what is intentionally excluded

### Slide 2: LUTRAM Elimination

- before vs after
- XPM migration
- routing / timing consequence

### Slide 3: PPA Tradeoff

- `shadow_data_region` occupancy
- `WNS`
- why full NIC and 256-beat DMA were rejected

### Slide 4: Hardware Validation Matrix

- `18` scenarios
- lengths `64 / 512 / 1472`
- `AES / SM4 / mixed_alt_50_50`
- `ACL off / on(non-matching)`

### Slide 5: Security And FastPath

- ACL counter behavior
- FastPath hit evidence
- replay / lock / reauth

### Slide 6: Boundary And Integrity

- tri-mix uncovered bugs
- what is not being over-claimed
- why this strengthens the engineering narrative

## Current Recommendation

- Use the matrix results as the primary quantitative benchmark asset.
- Run long-duration burn-in only on the already-defensible stable matrix scope.
- Do not headline tri-mix until ACL semantics and shadow-compare cleanliness are repaired.
