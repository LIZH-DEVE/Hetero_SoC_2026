# Step 19: AES Throughput Root-Cause Diagnosis

## Scope

This step does not change DUT behavior. It only adds measurement to:

- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tb/tests/tb_dma_subsystem_crypto_encdec.sv`

The goal is to determine whether the fresh AES throughput failure comes from:

1. test methodology,
2. AES single-engine latency / instance availability,
3. `crypto_bridge_top` scheduling utilization, or
4. downstream DMA / FIFO / TX back-pressure.

## Fresh baseline

The diagnostic run was executed on `2026-03-17` and produced:

- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tb_dma_subsystem_crypto_encdec_report.log`
- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/xsim.log`

Fresh timestamps:

- `tb_dma_subsystem_crypto_encdec_report.log`: `2026-03-17 23:15:43`
- `xsim.log`: `2026-03-17 23:15:43`
- instrumented TB: `2026-03-17 23:08:02`

Final regression summary from the fresh run:

- `Tests total=3 pass=2 fail=1`
- `OVERALL RESULT: FAIL`
- failing test: `test_throughput_aes`
- passing control test: `test_throughput_sm4`

This preserves the original symptom while giving new internal measurements.

## Instrumentation added

The testbench now logs, per run:

- block dispatch count and average dispatch gap
- block completion count and average completion gap
- per-instance starts, dones, busy percentage, average service cycles, min and max service cycles
- `collect_wait` percentage
- `dispatch_noinst` percentage
- mid FIFO full percentage
- out FIFO full percentage
- gearbox blocked percentage
- TX wait percentage
- PBM / mid FIFO / out FIFO peak occupancy

No RTL functional logic was modified in this step.

## Measured results

### AES

For all three measured sizes, AES misses the `150 MB/s` target:

| Size | System Throughput | Avg Dispatch Gap | Avg Done Gap | Avg Block Service | Dispatch-No-Inst |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1KB | 64.05 MB/s | 13.67 cyc | 13.67 cyc | 54.00 cyc | 34.06% |
| 64KB | 84.27 MB/s | 14.16 cyc | 14.16 cyc | 54.00 cyc | 48.94% |
| 1MB | 84.37 MB/s | 14.22 cyc | 14.22 cyc | 54.00 cyc | 49.02% |

Representative 1MB evidence from the fresh log:

- `[aes_tp_1048576B_run1] SYSTEM-LEVEL (with AXI/DMA): latency=932108 cyc, throughput=84.37 MB/s`
- `[aes_tp_1048576B_run1] DIAG blocks sched=65536 out=65536 avg_sched_gap=14.22 cyc avg_done_gap=14.22 cyc avg_block_service=54.00 cyc`
- `[aes_tp_1048576B_run1] DIAG pressure parallel_eff=94.91% pbm_max=31628 mid_max=1 out_max=1`
- `[aes_tp_1048576B_run1] DIAG stall_pct collect_wait=0.01% dispatch_noinst=49.02% mid_full=0.00% out_full=0.00% gb_blocked=0.00% tx_wait=0.00%`

Per-instance 1MB evidence is symmetric:

- each of 4 instances starts `16384` blocks
- each of 4 instances completes `16384` blocks
- each of 4 instances averages `54.00` service cycles
- each of 4 instances reaches `94.91%` busy time

### SM4 control case

The same diagnostic flow shows SM4 exceeding the target:

| Size | System Throughput | Avg Dispatch Gap | Avg Done Gap | Avg Block Service | Dispatch-No-Inst |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1KB | 103.37 MB/s system, 166.60 MB/s averaged TP line | 7.00 cyc | 7.00 cyc | 18.00 cyc | 0.00% |
| 64KB | 165.32 MB/s | 7.19 cyc | 7.19 cyc | 18.00 cyc | 0.00% |
| 1MB | 165.53 MB/s | 7.25 cyc | 7.25 cyc | 18.00 cyc | 0.00% |

Representative 1MB evidence from the fresh log:

- `[sm4_tp_1048576B_run1] SYSTEM-LEVEL (with AXI/DMA): latency=475112 cyc, throughput=165.53 MB/s`
- `[sm4_tp_1048576B_run1] DIAG blocks sched=65536 out=65536 avg_sched_gap=7.25 cyc avg_done_gap=7.25 cyc avg_block_service=18.00 cyc`
- `[sm4_tp_1048576B_run1] DIAG stall_pct collect_wait=0.01% dispatch_noinst=0.00% mid_full=0.00% out_full=0.00% gb_blocked=0.00% tx_wait=0.00%`

## Decision-complete conclusion

The fresh data rules out several candidate causes:

1. Not a downstream back-pressure problem.
   - `mid_full=0.00%`
   - `out_full=0.00%`
   - `gb_blocked=0.00%`
   - `tx_wait=0.00%`

2. Not a PBM feed starvation problem.
   - `collect_wait` stays around `0.01%` for large runs.

3. Not primarily a test-methodology artifact.
   - the same TB, clock, data size sweep, and measurement path show SM4 clearly above target.
   - AES and SM4 diverge in internal service metrics, not only in final MB/s.

4. Not best explained as a generic FPGA resource ceiling.
   - the limiting signature is algorithm-specific.
   - AES instances are nearly fully busy while still taking about `54 cycles/block`.
   - SM4 instances complete in about `18 cycles/block` and sustain the target.

The dominant root cause is therefore:

- AES block service latency is too high in the current architecture, which leaves the bridge in `dispatch with no available instance` for about half the run.

Secondary observation:

- `crypto_bridge_top` scheduling itself is not obviously broken. It is able to keep all 4 AES instances busy at about `95%`, but the AES service time is too long to sustain `150 MB/s` at `75 MHz`.

## Practical implication

At `75 MHz`, the current 4-lane AES path delivers about `84 MB/s`, not `150 MB/s`.

This means the next step is not in DMA, PBM, gearbox, or top-level TX export. The next meaningful optimization target is one of:

1. reduce AES per-block latency in `crypto_engine`,
2. change AES scheduling / overlap behavior in `crypto_bridge_top`, or
3. revise the AES throughput requirement if the current AES micro-architecture is intentional.

## Recommended next action

Do one focused AES design review covering:

- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/core/crypto/crypto_engine.sv`
- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/core/crypto/crypto_bridge_top.sv`

The review question should be:

- why AES consumes about `54 cycles/block` while SM4 consumes about `18 cycles/block` under the same 4-instance scheduler.

Until that review is done, the most defensible project statement is:

- AES throughput failure is real,
- its primary bottleneck is inside the AES compute path / instance availability,
- and there is no fresh evidence that DMA/PBM/TX-side pressure is the limiting factor.
