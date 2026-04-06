# DMA Crypto Thesis Data Table

Board-first acceptance source:
- `scripts/day21_performance_benchmark.py --bench-ip ...`
- `HCS_SOC/run_ax7020_udp_gateway_shadow_mirror_performance_check.ps1`
- Real AX7020 board `BENCH` control responses

Rule:
- Only real AX7020 board benchmark captures may fill acceptance rows.
- Simulation data may be cited separately as supporting analysis, but must not be used as acceptance evidence.

Current status:
- Current baseline board capture collected from `shadow_mirror_20260329_231856`.
- Current final acceptance capture collected from `shadow_mirror_20260401_191044`.
- Current acceptance bar for this phase is `avg_speedup >= 1.0x` per algorithm.
- `16 B / 32 B short-payload rows may remain below 1.0x`; acceptance is judged by average speedup, not isolated short rows.
- Historical baseline result was valid but below target:
  - AES avg speedup = `0.601748x`
  - SM4 avg speedup = `0.226816x`
- Stage 2 SG proof contract is now defined as `single-launch` descriptor batching with `1000 repeats`.
- Stage 2 SG proof is board-proven from `hybrid_perf_proof_20260331_181431`:
  - AES avg speedup = `4.877192x`
  - SM4 avg speedup = `2.847728x`
- Final `shadow_mirror` merge-back is board-proven and performance-proven from `shadow_mirror_20260401_191044`:
  - AES avg speedup = `2.726501x`
  - SM4 avg speedup = `2.055588x`
- Final acceptance image SHA256 = `F41015670B925DC863D2F53A66E965F3AB37C0DE8CC1FFE867B71BCD7CD45B26`
- Long-run JTAG soak is board-proven from `board_soak/shadow_mirror_20260401_224117`:
  - result = `PASS`
  - cycles completed = `128`
  - AES probes = `128`
  - SM4 probes = `128`
  - ACL probes = `12`
  - replay probes = `6`

## Module 1: Performance (Board Acceptance)

| Algorithm | Size | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Status |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| AES | 16 B | 4937 | 3344 | 4.937000 | 3.344000 | 3.090701 | 4.563035 | Final acceptance PASS |
| AES | 32 B | 9077 | 4457 | 9.077000 | 4.457000 | 3.362078 | 6.847112 | Final acceptance PASS |
| AES | 128 B | 33835 | 11216 | 33.835000 | 11.216000 | 3.607812 | 10.883587 | Final acceptance PASS |
| AES | 512 B | 132872 | 38102 | 132.872000 | 38.102000 | 3.674824 | 12.815108 | Final acceptance PASS |
| AES | 1472 B | 380728 | 105301 | 380.728000 | 105.301000 | 3.687169 | 13.331389 | Final acceptance PASS |
| SM4 | 16 B | 2634 | 2604 | 2.634000 | 2.604000 | 5.793010 | 5.859750 | Final acceptance PASS |
| SM4 | 32 B | 3927 | 3013 | 3.927000 | 3.013000 | 7.771219 | 10.128635 | Final acceptance PASS |
| SM4 | 128 B | 11577 | 5460 | 11.577000 | 5.460000 | 10.544209 | 22.357200 | Final acceptance PASS |
| SM4 | 512 B | 42178 | 15046 | 42.178000 | 15.046000 | 11.576681 | 32.452562 | Final acceptance PASS |
| SM4 | 1472 B | 118679 | 39046 | 118.679000 | 39.046000 | 11.828618 | 35.952686 | Final acceptance PASS |

Notes:
- PS software baseline = same-board `gateway_sw_encrypt_buffer()`
- Final hardware path = same-board descriptor-driven DMA batch executor merged back into `shadow_mirror` BENCH
- `SW Total (us)` and `HW Total (us)` are totals across `repeats`; average latency is derived as `total_us / repeats`
- Acceptance gate for this phase: `avg_speedup >= 1.0x`
- `16 B / 32 B short-payload rows may remain below 1.0x`
- Stage 2 SG proof target: `single-launch` batching with `1000 repeats`
- Stage 2 SG proof artifacts must report `Descriptor count`, `Doorbell count`, and last-descriptor polling evidence

## Module 2: Implementation (Vivado Reports)

| Item | Value | Status | Source |
|---|---:|---|---|
| SM4 core LUT/FF | Pending | Pending | `report_utilization -hierarchical` |
| AES core LUT/FF | Pending | Pending | `report_utilization -hierarchical` |
| Total LUT | `25736 / 53200 = 48.38%` | Collected | `udp_gateway_shadow_mirror_wrapper_utilization_placed.rpt` |
| Total FF | `30299 / 106400 = 28.48%` | Collected | `udp_gateway_shadow_mirror_wrapper_utilization_placed.rpt` |
| Block RAM Tile | `0.36%` | Collected | `udp_gateway_shadow_mirror_wrapper_utilization_placed.rpt` |
| Slice usage | `12419 / 13300 = 93.38%` | Collected | `udp_gateway_shadow_mirror_wrapper_utilization_placed.rpt` |
| Total Power (W) | Pending | Pending | `report_power` |
| Timing (Fmax / WNS) | Pending | Pending | `report_timing_summary` |

## Module 3: Analytical Derivation

| Item | Formula | Current Value | Status |
|---|---|---:|---|
| Hardware speedup vs PS software | `HW_throughput / SW_throughput` | AES `2.726501x`, SM4 `2.055588x` | Final acceptance PASS |
| AES area efficiency | `AES_Mbps / AES_LUT` | Pending | Pending implementation reports |
| SM4 area efficiency | `SM4_Mbps / SM4_LUT` | Pending | Pending implementation reports |
| Stall factor | `1 - HW_bw / Bus_peak_bw` | Pending | Pending implementation reports |

## Module 4: Reliability / Mechanism

| Item | Current Result | Status |
|---|---|---|
| Live AES functional path | Board-proven PASS | Collected |
| Live SM4 functional path | Board-proven PASS | Collected |
| Shadow AES mirror path | Board-proven PASS | Collected |
| Shadow SM4 mirror path | Board-proven PASS | Collected |
| DNA binding path | Board-proven PASS | Collected |
| ACL enforcement | Board-proven PASS | Collected |
| Replay rejection / lock / re-auth | Board-proven PASS | Collected |
| Wrong-port / unaligned contract | Board-proven PASS | Collected |
| Board performance BENCH capture | Final acceptance captured from `shadow_mirror_20260401_191044` | Collected |
| Stage 2 SG proof | `single-launch` descriptor batch board-proven from `hybrid_perf_proof_20260331_181431` | Collected |
| Full `shadow_mirror` merge-back | Board-proven and performance-proven on `xc7z020` | Collected |
| JTAG soak stability | `30` minute mixed soak PASS from `board_soak/shadow_mirror_20260401_224117` | Collected |

## Capture Commands

```powershell
powershell -ExecutionPolicy Bypass -File D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_performance_check.ps1 -Deploy -SdDrive E:
```

```powershell
py -3 D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\scripts\day21_performance_benchmark.py --bench-ip 192.168.1.20 --source-ip 192.168.1.11 --algos aes,sm4 --repeats 1000 --output-dir D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\doc\reports\board_benchmarks\manual_run
```

```powershell
powershell -ExecutionPolicy Bypass -File D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\run_ax7020_dma_gateway_hybrid_perf_proof_board_check.ps1 -Deploy -SdDrive E:
```

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_soak_check.ps1 -AssumeRunning
```
