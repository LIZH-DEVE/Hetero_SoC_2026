# tb_dma_subsystem_crypto_encdec Test Report

## 1. Scope
- Testbench: `tb/tests/tb_dma_subsystem_crypto_encdec.sv`
- DUT: `rtl/top/dma_subsystem.sv`
- Algorithm mode: AES-128 ECB / SM4 ECB
- Parallel mode: 16 blocks

## 2. Implemented Test Items
- `test_16_parallel_blocks`
- `test_throughput_aes` (1KB / 10KB / 100KB / 1MB, 3 repeats by default)
- `test_throughput_sm4` (1KB / 10KB / 100KB / 1MB, 3 repeats by default)
- `test_backpressure`
- `test_key_switch`
- `test_stability` (10000 operations by default)

## 3. Metrics Implemented
- Throughput (MB/s)
- Latency (cycles)
- Success rate
- Resource utilization monitoring
  - crypto instance busy ratio
  - output FIFO max utilization
  - PBM/max internal FIFO occupancy monitor

## 4. Current Execution Status
- Compile/elaboration: PASS (`xvlog + xelab`)
- Smoke runtime (1 us): PASS (simulation starts and enters test flow)
- Full regression (run-all): Not completed in this run (long runtime expected for full 10000-op stability + 1MB performance sweeps)

## 5. Target Criteria
| Metric | Target |
|---|---|
| Data integrity | 100% |
| AES throughput | >=150 MB/s |
| SM4 throughput | >=150 MB/s |
| Stability | 10000 operations no crash |
| Roundtrip consistency | 100% |

## 6. How To Run Full Regression
1. Run:
   - `vivado -mode batch -source sim/scripts/run_tb_dma_subsystem_crypto_encdec.tcl`
2. Check output:
   - `sim_output/tb_dma_subsystem_crypto_encdec/simulate.log`
   - `sim_output/tb_dma_subsystem_crypto_encdec/tb_dma_subsystem_crypto_encdec_report.log`
3. Extract throughput/latency/summary from `tb_dma_subsystem_crypto_encdec_report.log` into this report table.

