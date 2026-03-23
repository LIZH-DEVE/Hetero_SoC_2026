# Day18 Robustness Fix Step 18

Date: 2026-03-17

## Scope

Close the two real Day18 robustness gaps exposed by the repaired bench:

- runt frame rejection
- giant frame rejection

The fix was constrained to [`rx_parser.sv`](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/core/parser/rx_parser.sv), with follow-up updates only in the two affected benches:

- [`tb_day18_robustness.sv`](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tb/tb_day18_robustness.sv)
- [`tb_rx_parser_arp_sanity.sv`](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tb/tb_rx_parser_arp_sanity.sv)

## Root Cause

`rx_parser` already sees IPv4 `ip_total_len` in the IP header before it enters payload forwarding.

Before this fix, it checked:

- payload alignment
- malformed UDP length

But it never checked whether `Ethernet header (14B) + ip_total_len` violated the minimum or maximum Ethernet frame size contract.

As a result:

- runt packets were accepted
- giant packets were accepted

## RTL Change

In [`rx_parser.sv`](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/core/parser/rx_parser.sv):

- added:
  - `MIN_IPV4_TOTAL_LEN = 50`
  - `MAX_IPV4_TOTAL_LEN = 1504`
- added `frame_len_invalid_this_cycle`
- when `global_word_cnt == 4` (the IP header word carrying `ip_total_len`) the parser now transitions to `DROP` if the frame would be:
  - `< 64B`
  - `> 1518B`

This is an early drop, before payload forwarding begins, so the packet does not reach PBM/meta on these paths.

## Bench Adjustments

Two benches needed data-vector cleanup after the contract was tightened:

- [`tb_day18_robustness.sv`](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tb/tb_day18_robustness.sv)
  - the previous "normal aligned packet" was still a runt frame
  - updated to use a truly non-runt aligned packet (`ip_total_len=60`, `udp_len=40`, `8` payload words)
  - rollback case updated to the same legal frame size

- [`tb_rx_parser_arp_sanity.sv`](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tb/tb_rx_parser_arp_sanity.sv)
  - the stale-malformed regression case used a second UDP sample that was also a runt frame
  - updated helper to send configurable payload length
  - valid second packet now uses `ip_total_len=60`, `udp_len=40`, `8` payload words

## Fresh Verification

### 1. Day18 robustness

```powershell
D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv rtl\core\parser\rx_parser.sv rtl\core\pbm\pbm_controller.sv tb\tb_day18_robustness.sv
D:\Xilinx\Vivado\2024.1\bin\xelab.bat tb_day18_robustness -s tb_day18_robustness_dbg
D:\Xilinx\Vivado\2024.1\bin\xsim.bat tb_day18_robustness_dbg -runall
```

Result:

- Total Tests: `6`
- Passed: `6`
- Failed: `0`

Per-case:

- runt drop: `PASS`
- giant drop: `PASS`
- bad alignment drop: `PASS`
- malformed drop: `PASS`
- normal aligned accept: `PASS`
- PBM rollback on write error: `PASS`

### 2. rx_parser ARP sanity

```powershell
D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv rtl\core\parser\rx_parser.sv tb\tb_rx_parser_arp_sanity.sv
D:\Xilinx\Vivado\2024.1\bin\xelab.bat tb_rx_parser_arp_sanity -s tb_rx_parser_arp_sanity_dbg
D:\Xilinx\Vivado\2024.1\bin\xsim.bat tb_rx_parser_arp_sanity_dbg -runall
```

Result:

- `PASS: rx_parser forwarded ARP words, blocked bad frames, and honored ARP back-pressure`

### 3. Existing integration confidence

[`tb_day14_full_integration.sv`](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tb/tb_day14_full_integration.sv) had already been rerun fresh after the `rx_parser` change and remained green:

- `通过测试: 4`
- `失败测试: 0`

## Conclusion

Day18 robustness is now covered by a trustworthy, fresh regression, and the two previously missing robustness features are implemented:

- runt frame rejection
- giant frame rejection

The remaining open validation items after this step are no longer in Day18; they stay at:

- AES throughput target failure in `tb_dma_subsystem_crypto_encdec`
- bridge-only TX-last sanity blocked by XSim instability
- latest RTL changes still need board-level bitstream validation
