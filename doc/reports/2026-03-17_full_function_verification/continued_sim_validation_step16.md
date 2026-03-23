# Continued Simulation Validation Step 16

Date: 2026-03-17

## Scope

Fresh simulation verification for the remaining focused sanity benches after the TX output contract work:

- FastPath
- ARP parser/responder chain
- Security single-module sanities
- Day14 / Day15 phase-level regression benches
- Day18 robustness bench compile/run health

## Fresh PASS Results

### Focused module sanities

- `tb_fast_path_sanity.sv`
  - Result: `PASS: fast_path sanity verified eligible path plus bypass/drop classification semantics`
- `tb_day17_fastpath.sv`
  - Result: `Total Tests: 23 / Passed: 23 / Failed: 0`
- `tb_rx_parser_arp_sanity.sv`
  - Result: `PASS: rx_parser forwarded ARP words, blocked bad frames, and honored ARP back-pressure`
- `tb_arp_responder_sanity.sv`
  - Result: `PASS: arp_responder generated correct 7-word replies and preserved requests under back-pressure`
- `tb_arp_chain_sanity.sv`
  - Result: `PASS: rx_parser -> arp_responder chain preserved back-pressure and generated full 7-word replies`
- `tb_acl_match_engine_sanity.sv`
  - Result: `PASS: acl_match_engine sanity`
- `tb_acl_packet_filter_sanity.sv`
  - Result: `PASS: acl_packet_filter sanity`
- `tb_config_packet_auth_sanity.sv`
  - Result: `PASS: config_packet_auth sanity`
- `tb_key_vault_sanity.sv`
  - Result: `PASS: key_vault sanity`
  - Note: the bench needed a timing-contract update. `effective_key_valid` is a request-cycle pulse in the current RTL; the old bench sampled it one cycle late and produced a false failure.

### Phase-level regressions

- `tb_day15_hsm.sv`
  - Result: `Total Tests: 7 / Passed: 7 / Failed: 0`
  - Observed checks:
    - config packet auth valid path
    - invalid magic reject
    - replay reject
    - next valid sequence accept
    - DNA bind / unlock
    - derived key non-zero
    - key cleared when lock disabled
- `tb_day14_full_integration.sv`
  - Result: `通过测试: 4 / 失败测试: 0`
  - Bench claims satisfied checks for:
    - pcap generation
    - payload encryption path
    - checksum path
    - malformed packet handling

## New Findings

### FRESH-STEP16-1: `tb_day18_robustness.sv` is currently stale and does not elaborate

Status: `FAIL`

Observed during `xvlog/xelab` on:

- `rtl/core/parser/rx_parser.sv`
- `rtl/core/pbm/pbm_controller.sv`
- `tb/tb_day18_robustness.sv`

Concrete failures:

- invalid combination of procedural drivers on `pbm_usage_before`
- invalid combination of procedural drivers on `rollback_detected`
- width drift warning on `o_buffer_usage`
- unconnected `o_rec_src_mac`

Interpretation:

- this is not a tool glitch
- the robustness bench has drifted away from the current parser/PBM contract
- Day18 robustness is therefore **not currently covered by a trustworthy fresh regression**

## Supporting Commands

Representative fresh commands used in this step:

```powershell
D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv rtl\core\fast_path.sv tb\tb_day17_fastpath.sv
D:\Xilinx\Vivado\2024.1\bin\xelab.bat tb_day17_fastpath -s tb_day17_fastpath_dbg
D:\Xilinx\Vivado\2024.1\bin\xsim.bat tb_day17_fastpath_dbg -runall

D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv rtl\security\key_vault.sv tb\tb_key_vault_sanity.sv
D:\Xilinx\Vivado\2024.1\bin\xelab.bat tb_key_vault_sanity -s tb_key_vault_sanity_dbg
D:\Xilinx\Vivado\2024.1\bin\xsim.bat tb_key_vault_sanity_dbg -runall

D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv -prj day15_compile.prj
D:\Xilinx\Vivado\2024.1\bin\xelab.bat xil_defaultlib.tb_day15_hsm -s tb_day15_hsm_dbg
D:\Xilinx\Vivado\2024.1\bin\xsim.bat tb_day15_hsm_dbg -runall

D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv -prj day14_compile.prj
D:\Xilinx\Vivado\2024.1\bin\xelab.bat xil_defaultlib.tb_day14_full_integration -s tb_day14_full_integration_dbg
D:\Xilinx\Vivado\2024.1\bin\xsim.bat tb_day14_full_integration_dbg -runall
```

## Current Residual Risk After Step 16

The current simulation picture is materially better than before this run, but the project is still not at "everything verified" status because these items remain open:

- `tb_day18_robustness.sv` is stale and currently broken
- `tb_crypto_bridge_tx_last_sanity.sv` is still blocked by XSim instability under hierarchical force
- `tb_dma_subsystem_crypto_encdec.sv` still has a fresh AES throughput-target failure even though functional enc/dec paths pass
- board-level verification has not yet been rerun for the latest TX contract changes
- real host-to-board network capture remains outside this simulation-only step
