# Step 15: Top-Level TX Output Contract Closure

## Scope

This step only closes the current top-level raw TX export contract for:

- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/dma_subsystem.sv`
- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/crypto_dma_subsystem.sv`
- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/core/crypto/crypto_bridge_top.sv`

No `tx_stack` integration was added. `tx_axis_tlast` is now defined as the last 32-bit beat of each 128-bit crypto block. `tx_axis_tkeep` remains fixed at `4'hF`.

## RTL changes

1. `crypto_bridge_top`
   - Added internal-visible output `o_tx_last`
   - Widened output FIFO payload from 32 bits to 33 bits
   - Packed `{gb_dout_last, gb_dout}` through the output FIFO
   - Recovered `o_tx_last` and `o_tx_data` from FIFO output

2. `dma_subsystem`
   - Added `crypto_to_dma_last`
   - Propagated `crypto_bridge_top.o_tx_last` to `tx_axis_tlast` in raw TX modes
   - Added `bridge_tx_rd_en`
   - In `loopback_mode == 2'b10`, TX FIFO consumption is now driven by `tx_axis_tready && !crypto_to_dma_empty`

3. `crypto_dma_subsystem`
   - Applied the same `o_tx_last` and `bridge_tx_rd_en` propagation as `dma_subsystem`

## New focused sanity TBs

- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tb/tb_dma_tx_output_sanity.sv`
- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tb/tb_crypto_dma_tx_output_sanity.sv`
- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tb/tb_crypto_bridge_tx_last_sanity.sv`
- Compile list:
  - `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/sim/scripts/tx_output_contract_compile.prj`

## Fresh verification evidence

### PASS

1. `tb_dma_tx_output_sanity`
   - Result: `PASS: dma_subsystem tx output exposed block-level tlast`
   - Covered:
     - single block
     - two consecutive blocks
     - TX held at `tready=0` from start, then resumed
   - Verified:
     - `tlast` at beats 4 and 8 as expected
     - `tkeep == 4'hF`

2. `tb_crypto_dma_tx_output_sanity`
   - Result: `PASS: crypto_dma_subsystem tx output exposed block-level tlast`
   - Covered:
     - single block
     - two consecutive blocks
     - TX held at `tready=0` from start, then resumed
   - Verified:
     - `tlast` at beats 4 and 8 as expected
     - `tkeep == 4'hF`

3. Regression: `tb_dma_ingress_security_chain_sanity`
   - Result: `PASS: dma ingress security chain sanity`

4. Regression: `tb_day16_acl`
   - Result: `4/4 PASS`

### PASS with unrelated existing failure still present

5. Existing main-path crypto/dma regression: `tb_dma_subsystem_crypto_encdec`
   - Functional roundtrip:
     - AES roundtrip PASS
     - SM4 roundtrip PASS
   - Throughput:
     - SM4 target PASS
     - AES throughput target FAIL
   - Final summary from TB:
     - `Tests: total=3 pass=2 fail=1`
     - `Checks: total=8 pass=5 fail=3`
     - `OVERALL RESULT: FAIL`
   - Observed failure mode is the existing AES throughput threshold inside that TB, not TX block-boundary correctness.

### BLOCKED / unstable

6. `tb_crypto_bridge_tx_last_sanity`
   - The focused bridge-only TB exists and compiles/elaborates.
   - Attempted hierarchical `force/release` based injection into `crypto_bridge_top` causes XSim to shut down unexpectedly during initialization.
   - `xsimkernel.log` shows the kernel runs, but the wrapper process reports an initialization failure and emits `xsimcrash.log`.
   - Status for this one TB is therefore `BLOCKED by XSim instability on hierarchical force`.

## Conclusion

The top-level raw TX contract is now closed and directly verified at the two real exported top modules:

- `dma_subsystem`
- `crypto_dma_subsystem`

Specifically:

- `tx_axis_tlast` is no longer a constant zero placeholder
- `tx_axis_tlast` now marks the last 32-bit beat of each 128-bit crypto block
- `tx_axis_tkeep` remains `4'hF`
- `loopback_mode == 2'b10` now actually consumes the crypto bridge TX FIFO using `tx_axis_tready`

The only open item in this step is the bridge-only focused sanity TB, which is blocked by XSim instability in the chosen hierarchical injection method, not by a known RTL mismatch.
