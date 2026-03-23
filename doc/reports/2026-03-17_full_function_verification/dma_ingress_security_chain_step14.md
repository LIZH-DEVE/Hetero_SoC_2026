# DMA Ingress Security Chain Step 14

## Scope

This step verifies the real ingress security chain inside `rtl/top/dma_subsystem.sv`:

- `rx_wr`
- `config_packet_auth`
- `acl_packet_filter`
- `pbm_controller`

The verification target is the actual integrated path, not the isolated ACL block.

## Root Cause Fixed

`config_packet_auth` emits two auth header words before the 7-word simplified network header.  
`acl_packet_filter` matches on the semantic tuple:

`{protocol, src_ip, src_port, dst_ip, dst_port}`

Without an internal strip stage, `auth_en=1` traffic can never produce a semantic ACL hit or miss.

`rtl/top/dma_subsystem.sv` now strips the first two auth header beats before sending traffic into the ACL stage when `auth_en=1`.

## New Verification Artifact

- `tb/tb_dma_ingress_security_chain_sanity.sv`
- `sim/scripts/dma_ingress_security_chain_compile.prj`

## Verified Cases

- A1: `auth_en=0, acl_en=0` direct pass to PBM
- A2: `auth_en=0, acl_en=1` ACL miss
- A3: `auth_en=0, acl_en=1` ACL hit
- B1: short packet bypass (`< 7 words`)
- B2: auth fail blocks before ACL/PBM
- B3: auth pass + ACL hit
- B4: auth pass + ACL miss
- C1: PBM back-pressure with forced PBM drain gating in TB
- C2: multi-packet sequence `miss -> hit -> short bypass -> miss`
- D1: minimum PBM write-error rollback sanity

## Commands

```powershell
D:\Xilinx\Vivado\2024.1\bin\xvlog.bat -sv -prj sim/scripts/dma_ingress_security_chain_compile.prj
D:\Xilinx\Vivado\2024.1\bin\xelab.bat -debug typical -relax -snapshot tb_dma_ingress_security_chain_sanity_behav xil_defaultlib.tb_dma_ingress_security_chain_sanity
D:\Xilinx\Vivado\2024.1\bin\xsim.bat tb_dma_ingress_security_chain_sanity_behav -runall
```

## Result

Direct simulation result:

- `PASS: dma ingress security chain sanity`

Regression rerun after the integration fix:

- `tb_acl_packet_filter_sanity.sv` passed
- `tb_acl_match_engine_sanity.sv` passed
- `tb_config_packet_auth_sanity.sv` passed
- `tb_day16_acl.sv` passed (`4/4 PASS`)

## Evidence Notes

- Short packets still bypass ACL by current RTL contract. This is now verified behavior, not an unconfirmed suspicion.
- The PBM back-pressure case in this step depends on hierarchical force/release of `dut.bridge_rd_pbm` in TB, because the standalone simulation setup does not naturally create the same downstream drain behavior as a full board flow.
- The PBM write-error rollback case is also simulation-only and relies on hierarchical forcing of `dut.u_pbm.i_wr_error`.

## Current Conclusion

- The ingress security chain in `dma_subsystem` is now verified at simulation level.
- The auth-enabled ACL path had a real integration bug and is now fixed.
- Remaining work should move upward to board-level or full data-path validation, not back down to isolated ACL tuple semantics.
