# Day18 Robustness Revalidation Step 17

Date: 2026-03-17

## Scope

Repair the stale `tb_day18_robustness.sv` bench so it reflects the current `rx_parser` + `pbm_controller` contract, then run it fresh to separate:

- bench drift / false failures
- actual missing robustness features

## Bench Repairs

Updated [`tb_day18_robustness.sv`](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tb/tb_day18_robustness.sv) to match current RTL behavior:

- removed invalid multiple procedural drivers on monitor signals
- fixed `o_buffer_usage` width to match `pbm_controller`
- connected current `rx_parser` outputs including `o_rec_src_mac`, `o_rec_valid`, `o_arp_*`
- replaced stale "sample `meta_valid` long after the packet" logic with pulse-capture monitors
- isolated every test case with a local reset so PBM state does not leak between cases
- separated two different recovery classes:
  - header-time drop (`bad align`, `malformed`)
  - PBM rollback on write error (`tuser` on final beat)

## Fresh Verification Command

```powershell
D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv rtl\core\parser\rx_parser.sv rtl\core\pbm\pbm_controller.sv tb\tb_day18_robustness.sv
D:\Xilinx\Vivado\2024.1\bin\xelab.bat tb_day18_robustness -s tb_day18_robustness_dbg
D:\Xilinx\Vivado\2024.1\bin\xsim.bat tb_day18_robustness_dbg -runall
```

## Fresh Result

Simulation summary:

- Total Tests: `6`
- Passed: `4`
- Failed: `2`

Per-case result:

1. `Runt frame drop requirement`
   - Result: `FAIL`
   - Observed: `meta_seen=1`, `pbm_write_beats=4`
   - Interpretation: current `rx_parser` does not enforce minimum Ethernet frame size

2. `Giant frame drop requirement`
   - Result: `FAIL`
   - Observed: `meta_seen=1`, `pbm_write_beats=376`
   - Interpretation: current `rx_parser` does not enforce maximum Ethernet frame size

3. `Bad alignment drop`
   - Result: `PASS`

4. `Malformed UDP length drop`
   - Result: `PASS`

5. `Normal aligned packet accepted`
   - Result: `PASS`

6. `PBM rollback on write error`
   - Result: `PASS`

## Conclusion

The old Day18 result was not trustworthy because the bench itself had drifted.

After repairing the bench, the current trustworthy status is:

- rollback path works for real PBM write errors
- malformed and bad-alignment rejection works
- **minimum-frame and maximum-frame enforcement are missing in the current RTL**

That means Day18 is now covered by a credible fresh regression, and it identifies two real missing robustness features rather than bench noise.
