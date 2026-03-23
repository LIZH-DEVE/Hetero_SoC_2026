# DMA Crypto Thesis Data Table (Draft)

Data source:
- Simulation log: `HCS_SOC/HCS_SOC.sim/sim_1/behav/xsim/tb_dma_subsystem_crypto_encdec_report.log`
- Clock: 100 MHz (`CLK_PERIOD_NS = 10 ns`)
- Run switches in current log:
  - `RUN_FUNC=0 RUN_TP_AES=0 RUN_TP_SM4=1 RUN_BACKPRESSURE=0 RUN_KEY_SWITCH=0 RUN_STABILITY=0`
  - `THROUGHPUT_WARMUP=1 THROUGHPUT_REPEAT=3`
- Run result summary:
  - `Tests: total=1 pass=0 fail=1`
  - `Checks: total=4 pass=3 fail=1`
  - `SuccessRate: 75.00%`
  - `OVERALL RESULT: FAIL`

## Module 1: Performance (Simulation)

| Algorithm | Size | Avg Throughput (MB/s) | Avg Latency (cycles) | Avg Latency (ns) | Status |
|---|---:|---:|---:|---:|---|
| AES | 1 KB | 132.64 | 772 | 7,720 | Collected |
| AES | 10 KB | 205.99 | 4,974 | 49,740 | Collected |
| AES | 100 KB | 219.49 | 46,654 | 466,540 | Collected |
| AES | 1 MB | 220.57 | 475,396 | 4,753,960 | Collected |
| SM4 | 1 KB | 130.45 | 785 | 7,850 | Collected (below target) |
| SM4 | 10 KB | 205.46 | 4,987 | 49,870 | Collected |
| SM4 | 100 KB | 219.43 | 46,667 | 466,670 | Collected |
| SM4 | 1 MB | 220.56 | 475,409 | 4,754,090 | Collected |

Notes:
- Current run has functional pass for 16-block roundtrip:
  - AES roundtrip: PASS
  - SM4 roundtrip: PASS
- In this run, check `AES throughput >= 150MB/s @1024B` is FAIL; 10KB/100KB/1MB are PASS.
- In current SM4-only run, `SM4 throughput >= 150MB/s` fails only at `1024B`; 10KB/100KB/1MB are PASS.

## Module 2: Implementation (Vivado Reports)

| Item | Value | Status | Source |
|---|---:|---|---|
| SM4 core LUT/FF | TBD | Pending | `report_utilization -hierarchical` |
| AES core LUT/FF | TBD | Pending | `report_utilization -hierarchical` |
| Total LUT | TBD | Pending | `report_utilization` |
| Total Power (W) | TBD | Pending | `report_power` |
| Timing (Fmax / WNS) | TBD | Pending | `report_timing_summary` |

## Module 3: Analytical Derivation

| Item | Formula | Current Value | Status |
|---|---|---:|---|
| Software-hardware speedup | `HW_throughput / SW_throughput` | TBD | Pending |
| Stall factor | `1 - HW_bw / Bus_peak_bw` | TBD | Pending |
| AES area efficiency | `AES_Mbps / AES_LUT` | TBD | Pending |
| SM4 area efficiency | `SM4_Mbps / SM4_LUT` | TBD | Pending |

## Module 4: Reliability / Mechanism

| Item | Current Result | Status |
|---|---|---|
| AES 16-block roundtrip | PASS | Collected |
| SM4 16-block roundtrip | PASS | Collected |
| Throughput test count | `test_throughput_sm4=FAIL` (only 1KB threshold miss) | Collected |
| Backpressure | Not run in this data batch | Pending |
| Key switch | Not run in this data batch | Pending |
| Stability (10000 ops) | Not run in this data batch | Pending |

## Fast Fill Commands

```tcl
# Utilization / power / timing
open_run impl_1
report_utilization -hierarchical -file util_hier.rpt
report_utilization -file util_top.rpt
report_power -file power.rpt
report_timing_summary -file timing.rpt
```

```tcl
# Throughput-only run (SM4)
close_sim
set_property -name {xsim.simulate.xsim.more_options} -value {+RUN_FUNC=0 +RUN_TP_AES=0 +RUN_TP_SM4=1 +RUN_BACKPRESSURE=0 +RUN_KEY_SWITCH=0 +RUN_STABILITY=0 +THROUGHPUT_SIZE_COUNT=4 +THROUGHPUT_REPEAT=3 +THROUGHPUT_WARMUP=1 +PBM_COMMIT_WORDS=256 +RESET_EACH_TRANSFER=0} [get_filesets sim_1]
launch_simulation
run all
```
