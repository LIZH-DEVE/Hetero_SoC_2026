## Step 24: Stage1 Control Chain Applied-Value Fix

### Scope
- Convert Stage1 control from CSR direct-use to write-pulse-driven applied control inside `dma_subsystem`
- Add applied-value AXI-Lite readback window
- Update Stage1 simulation and board app to verify applied control before ARP/UDP injection

### RTL / Software Changes
- Updated [`rtl/core/axil_csr.sv`](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/core/axil_csr.sv)
  - Added write-enable outputs:
    - `o_net_cfg0_we`
    - `o_net_local_ip_we`
    - `o_net_local_mac_lo_we`
    - `o_net_local_mac_hi_we`
  - Added applied-value readback inputs:
    - `i_net_applied_cfg0`
    - `i_net_applied_local_ip`
    - `i_net_applied_local_mac_lo`
    - `i_net_applied_local_mac_hi`
  - Added readback addresses:
    - `0xBC` `NET_APPLIED_CFG0`
    - `0xC0` `NET_APPLIED_LOCAL_IP`
    - `0xC4` `NET_APPLIED_LOCAL_MAC_LO`
    - `0xC8` `NET_APPLIED_LOCAL_MAC_HI`

- Updated [`rtl/top/dma_subsystem.sv`](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/dma_subsystem.sv)
  - Added applied control registers:
    - `stage1_network_enable`
    - `stage1_ingress_inject_sel`
    - `stage1_arp_enable`
    - `stage1_local_ip`
    - `stage1_local_mac_lo`
    - `stage1_local_mac_hi`
  - Applied control is now updated only on matching AXI-Lite write pulses.
  - Reset defaults:
    - `network_enable = 0`
    - `ingress_inject_sel = 0`
    - `arp_enable = 1`
    - `local_ip = 32'hC0A8_0114`
    - `local_mac = 48'h020A_3500_0120`
  - Stage1 muxing and Stage1 module inputs now consume applied control, not raw CSR outputs.

- Updated [`tb/tb_dma_subsystem_network_inject_sanity.sv`](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tb/tb_dma_subsystem_network_inject_sanity.sv)
  - Added control correctness checks for:
    - reset defaults
    - write/update of `NET_CFG0`
    - write/update of `NET_LOCAL_IP`
    - stability of untouched applied values
  - Existing ARP/UDP injection tests now validate `NET_APPLIED_*` before protocol checks.

- Updated [`HCS_SOC/network_inject_app/src/main.c`](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/network_inject_app/src/main.c)
  - Added `NET_APPLIED_*` register definitions.
  - Added applied-control verification step before ARP/UDP injection.
  - App now prints `CONTROL_MISMATCH` and stops if programmed values do not reach the applied readback window.

### Fresh Verification Evidence
- Stage1 compile:
  - `xvlog -sv -prj sim/scripts/dma_stage1_network_compile.prj`
  - PASS
- Stage1 simulation:
  - `xelab xil_defaultlib.tb_dma_subsystem_network_inject_sanity -s tb_dma_subsystem_network_inject_sanity_dbg`
  - `xsim tb_dma_subsystem_network_inject_sanity_dbg -runall`
  - PASS: `dma_subsystem accepted AXI-Lite packet injection and captured ARP/UDP reply frames`
- Required regressions:
  - `tb_rx_parser_arp_sanity`: PASS
  - `tb_arp_chain_sanity`: PASS
  - `tb_day16_acl`: 4/4 PASS
  - `tb_dma_ingress_security_chain_sanity`: PASS
- `network_inject_app.elf` rebuilt successfully.
- New authoritative bitstream rebuilt successfully:
  - Path: [`HCS_SOC.runs/impl_1/design_1_wrapper.bit`](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit)
  - Timestamp: `2026-03-18 14:03:50`
  - SHA256: `B78A241A4ECFF5FDB0EF923FCB0544F3E72D90F04C49B2510F06ECFF52F42505`

### Current Board Blocker
- Board validation could not proceed to Stage1 applied-control readback because JTAG target enumeration regressed again.
- Fresh evidence:
  - `xsdb` `jtag targets` output was empty
  - `xsdb` `targets` output was empty
  - `run_board_smoke.ps1 -Action status` failed with `Context does not support memory read`
  - `capture_network_inject_log.ps1` failed in `ps7_init` with:
    - `AHB AP transaction error`
    - `Memory read error at 0xF8007080`
- Windows device state at time of failure:
  - `COM9` (CP210x UART) remained present
  - FTDI/Xilinx JTAG-side USB devices were not in a healthy enumerable state

### Decision
- RTL and simulation side of the applied-control fix are complete.
- Board-side Stage1 validation is currently blocked by hardware/JTAG enumeration, not by an identified RTL failure.
- Next action after hardware recovery:
  - rerun [`capture_network_inject_log.ps1`](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/capture_network_inject_log.ps1)
  - verify `NET_APPLIED_*`
  - then continue ARP/UDP Stage1 board validation
