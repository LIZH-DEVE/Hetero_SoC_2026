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
- Current final acceptance capture collected from `shadow_mirror_20260405_204158`.
- Current acceptance bar for this phase is `avg_speedup >= 1.0x` per algorithm.
- `16 B / 32 B short-payload rows may remain below 1.0x`; acceptance is judged by average speedup, not isolated short rows.
- Historical baseline result was valid but below target:
  - AES avg speedup = `0.601748x`
  - SM4 avg speedup = `0.226816x`
- Stage 2 SG proof contract is now defined as `single-launch` descriptor batching with `1000 repeats`.
- Stage 2 SG proof is board-proven from `hybrid_perf_proof_20260331_181431`:
  - AES avg speedup = `4.877192x`
  - SM4 avg speedup = `2.847728x`
- Final `shadow_mirror` merge-back is board-proven and performance-proven from `shadow_mirror_20260405_204158`:
  - AES avg speedup = `2.773757x`
  - SM4 avg speedup = `2.102749x`
- Final acceptance image SHA256 = `8D8501A0FD5A59B8511DA88507E20068DFC3D866E7E9CCD1A8AD47F50B2C8A72`
- SD cold-start post-confirmation is board-proven from `2026-04-02_shadow_mirror_cold_start_post_confirmation.md`
- Long-run JTAG soak is board-proven from `board_soak/shadow_mirror_20260401_224117`:
  - result = `PASS`
  - cycles completed = `128`
  - AES probes = `128`
  - SM4 probes = `128`
  - ACL probes = `12`
  - replay probes = `6`
- SD cold-start soak is board-proven from `board_soak/shadow_mirror_20260402_215701`:
  - result = `PASS`
  - cycles completed = `124`
  - AES probes = `124`
  - SM4 probes = `124`
  - ACL probes = `12`
  - replay probes = `6`
  - evidence mode = `control_data_after_manual_power_cycle`

## Module 1: Performance (Board Acceptance)

| Algorithm | Size | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Status |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| AES | 16 B | 4899 | 3186 | 4.899000 | 3.186000 | 3.114674 | 4.789325 | Final acceptance PASS |
| AES | 32 B | 9039 | 4293 | 9.039000 | 4.293000 | 3.376212 | 7.108683 | Final acceptance PASS |
| AES | 128 B | 33807 | 11050 | 33.807000 | 11.050000 | 3.610800 | 11.047087 | Final acceptance PASS |
| AES | 512 B | 132880 | 37920 | 132.880000 | 37.920000 | 3.674603 | 12.876615 | Final acceptance PASS |
| AES | 1472 B | 380826 | 105118 | 380.826000 | 105.118000 | 3.686220 | 13.354598 | Final acceptance PASS |
| SM4 | 16 B | 2641 | 2455 | 2.641000 | 2.455000 | 5.777656 | 6.215393 | Final acceptance PASS |
| SM4 | 32 B | 3935 | 2862 | 3.935000 | 2.862000 | 7.755420 | 10.663025 | Final acceptance PASS |
| SM4 | 128 B | 11585 | 5279 | 11.585000 | 5.279000 | 10.536928 | 23.123757 | Final acceptance PASS |
| SM4 | 512 B | 42185 | 14892 | 42.185000 | 14.892000 | 11.574760 | 32.788158 | Final acceptance PASS |
| SM4 | 1472 B | 118688 | 38995 | 118.688000 | 38.995000 | 11.827721 | 35.999707 | Final acceptance PASS |

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
| Hardware speedup vs PS software | `HW_throughput / SW_throughput` | AES `2.773757x`, SM4 `2.102749x` | Final acceptance PASS |
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
| Board performance BENCH capture | Final acceptance captured from `shadow_mirror_20260405_204158` | Collected |
| Stage 2 SG proof | `single-launch` descriptor batch board-proven from `hybrid_perf_proof_20260331_181431` | Collected |
| Full `shadow_mirror` merge-back | Board-proven and performance-proven on `xc7z020` | Collected |
| JTAG soak stability | `30` minute mixed soak PASS from `board_soak/shadow_mirror_20260401_224117` | Collected |
| SD cold-start soak stability | `30` minute cold-start soak PASS from `board_soak/shadow_mirror_20260402_215701` | Collected |

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

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_soak_check.ps1 -ColdStart -DurationMinutes 30 -CycleIntervalSeconds 15
```
