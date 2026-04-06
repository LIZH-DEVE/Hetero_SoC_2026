# 2026-04-06 Shadow Mirror Matrix And Tri-Mix Validation

## Scope

- Target system: active `udp_gateway_shadow_mirror_wrapper` release baseline
- Verification mode: board-online `SD` path, no RTL changes during this run
- Goal:
  - finish the 18-scenario host benchmark matrix
  - probe state-switch stress using a tri-mix traffic pattern
  - define what is defensible for a 12-hour burn-in claim

## 1. 18-Scenario Benchmark Matrix

### Result

- Status: `PASS`
- Artifact root:
  - [board_bench_matrix/shadow_mirror_20260406_110058](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/board_bench_matrix/shadow_mirror_20260406_110058)
- Primary summary:
  - [bench_matrix_summary.md](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/board_bench_matrix/shadow_mirror_20260406_110058/bench_matrix_summary.md)
- Raw report:
  - [bench_matrix_report.json](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/board_bench_matrix/shadow_mirror_20260406_110058/bench_matrix_report.json)
- CSV:
  - [bench_matrix_results.csv](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/board_bench_matrix/shadow_mirror_20260406_110058/bench_matrix_results.csv)

### Coverage

- Load modes:
  - `aes_only`
  - `sm4_only`
  - `mixed_alt_50_50`
- Payload lengths:
  - `64B`
  - `512B`
  - `1472B`
- ACL modes:
  - `acl_off`
  - `acl_on_nonmatching`

### Hard numbers

- All `18` scenarios reached:
  - `Success = 200 / 200`
  - `Timeouts = 0`
  - `Mismatches = 0`
- Baseline BENCH snapshot:
  - AES avg speedup: `2.774736x`
  - SM4 avg speedup: `2.105868x`

### What this proves

- The current release baseline is stable for:
  - pure `AES`
  - pure `SM4`
  - `AES/SM4` alternating mixed load
- This proof is valid for the matrix scope above.
- This does not automatically prove correctness under `FastPath-hit + active AES + ACL-hit` concurrent state switching.

## 2. Tri-Mix Stress Probe

### Traffic pattern

Each cycle injected three packets in sequence:

1. `64B` AES packet from fastpath-trained source port
2. `1472B` AES packet through the active datapath
3. `64B` AES packet from ACL-blocked source port `54060`

### Host-side cycle result

- Cycles executed: `60`
- `fastpath_aes64_ok = 60`
- `aes1472_ok = 60`
- `acl_block_ok = 60`
- `acl_drop_count_before = 0`
- `acl_drop_count_after = 60`
- `acl_drop_delta = 60`
- Runtime: `56.248s`

UART capture:
- [board_uart_trimix_20260406_111657.txt](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/board_uart_trimix_20260406_111657.txt)

### New findings

#### Finding A: ACL counter increments, but end-to-end blocking is not absolute

Single-packet retest with a longer receive window showed:

- `reply_received = 1`
- `elapsed_s = 0.375179`
- `acl_drop_count_after = 1`

This means:

- the ACL drop counter increments
- the UART emits `SHADOW_ACL_DROP PASS`
- but the blocked source can still receive a delayed `LIVE_AES` response

This is not consistent with a strong end-to-end claim of "ACL-hit implies no reply".

#### Finding B: tri-mix switching triggers shadow compare failures on `1472B`

The UART log repeatedly contains:

- `shadow compare fail algo=AES local_port=4660 actual_len=1472`

At the same time, the log also shows:

- `SHADOW_FASTPATH PASS actual_len=64`
- `FASTPATH_FALLBACK_COUNT count=...` with `0`
- `LIVE_AES PASS len=1472`

So the system is not deadlocking, but the shadow-compare path is not clean under this mixed stress pattern.

## 3. Verification Boundary

### Defensible today

- `18`-scenario matrix result is defensible
- `AES/SM4` mixed load without ACL-hit/FastPath-hit interleave is defensible
- `FastPath` standalone board check is defensible
- `ACL` counter behavior is defensible

### Not defensible today

- "ACL-hit packet always gets no response"
- "FastPath-hit + active AES + ACL-hit tri-mix is fully clean"
- "12-hour zero-loss burn-in under tri-mix state churn"

## 4. Burn-In Recommendation

### Recommended 12-hour burn-in scope

Run only the currently defensible stable mainline:

- 18-scenario benchmark matrix
- no additional tri-mix ACL/FastPath interleave injection
- acceptance:
  - every iteration must complete
  - every scenario must stay at `200/200`
  - no timeout
  - no mismatch

### Do not use for thesis headline yet

- tri-mix stress with ACL-hit and FastPath-hit in the same loop

That path has already produced actionable bugs and should be described as an open risk, not a finished capability.

### Ready-to-run 12-hour command

```powershell
$repo = 'D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026'
$burnRoot = Join-Path $repo ('doc\reports\board_burnin\shadow_mirror_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $burnRoot | Out-Null
$end = (Get-Date).AddHours(12)
$iter = 0
while ((Get-Date) -lt $end) {
    $iter++
    $log = Join-Path $burnRoot ('iter_{0:D4}.log' -f $iter)
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $repo 'HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_bench_matrix.ps1') `
        -AssumeRunning `
        -RequestsPerScenario 200 `
        -BenchRepeats 1000 *>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) {
        Write-Host ('Burn-in stopped on iteration {0}' -f $iter)
        break
    }
}
```

## 5. Thesis / Defense Framing

### Campaign 1: LUTRAM elimination

Use:

- `LUT as Memory = 10056` historical hotspot
- current top-level placed value `267 / 17400 = 1.53%`

Core framing:

> The design did not "just optimize code"; it restructured storage topology around XPM-backed memory placement, releasing routing capacity from distributed RAM hotspots and reopening timing margin on a resource-constrained XC7Z020 fabric.

### Campaign 2: cold PPA tradeoff

Use:

- `shadow_data_region Slice = 10407 / 10944 = 95.65%`
- `WNS = 4.561ns`

Core framing:

> Under a fabric region already driven to 95.65% Slice occupancy, the system deliberately rejected a full NIC datapath and 256-beat DMA expansion in order to preserve a positive timing moat and sustain a repeatable 2.7x-class acceleration baseline.

### Campaign 3: CBC physical isolation

Use:

- [2026-04-05-shadow-mirror-cbc-readiness.md](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/superpowers/plans/2026-04-05-shadow-mirror-cbc-readiness.md)

Core framing:

> CBC was not merged blindly into a block-oriented fast datapath. The project stopped at Phase 1 readiness, preserving metadata continuity and packet-atomic state capture while explicitly isolating XOR/chaining logic until a packet-aware transport contract can support it without destroying throughput claims.

## 6. Current Position

- Matrix benchmark phase: complete
- Tri-mix stress phase: incomplete, bug found
- 12-hour burn-in claim:
  - allowed for stable matrix scope
  - blocked for tri-mix scope
