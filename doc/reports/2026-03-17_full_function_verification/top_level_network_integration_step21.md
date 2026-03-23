# Step 21: Top-Level Network Integration Reality Check

Date: 2026-03-18

## Purpose

This step answered a practical board-closure question:

Can the current programmed top-level honestly support board-level ARP/UDP closure, or are those modules still only verified in simulation?

## Evidence Chain

### 1. The board design instantiates `dma_subsystem_v2_wrapper`

Generated BD wrapper:

- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.gen/sources_1/bd/system/ip/system_dma_subsystem_v2_wra_0_0/synth/system_dma_subsystem_v2_wra_0_0.v`

Relevant lines:

- module IP is `dma_subsystem_v2_wrapper`
- exposed streaming ports are only:
  - `rx_wr_valid`
  - `rx_wr_data`
  - `rx_wr_last`
  - `rx_wr_ready`
  - `tx_axis_tdata`
  - `tx_axis_tvalid`
  - `tx_axis_tlast`
  - `tx_axis_tkeep`
  - `tx_axis_tready`

This means the actual board image is centered on a raw ingress/egress stream wrapper around `dma_subsystem`.

### 2. The handwritten wrapper matches the generated wrapper

Source wrapper:

- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/dma_subsystem_v2_wrapper.v`

Relevant lines:

- line 3: `module dma_subsystem_v2_wrapper`
- line 34: `input wire rx_wr_valid`
- line 38: `output wire [31:0] tx_axis_tdata`
- line 106: instantiates `dma_subsystem`

No protocol-stack-specific top-level ports appear here either.

### 3. `dma_subsystem` currently integrates security ingress, not the network stack

Source:

- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/dma_subsystem.sv`

Relevant hits:

- line 439: `config_packet_auth u_cfg_auth`
- line 529: `acl_packet_filter u_acl_filter`

Searches for the following inside `dma_subsystem.sv` returned no instantiation hits:

- `rx_parser`
- `arp_responder`
- `tx_stack`
- `fast_path`
- `packet_dispatcher`

## Conclusion

The current board top-level does **not** yet provide a fully integrated network protocol path.

What is board-integrated today:

- raw ingress stream into `dma_subsystem`
- security ingress chain pieces inside `dma_subsystem`
  - `config_packet_auth`
  - `acl_packet_filter`
- raw `tx_axis_*` export
- crypto / DMA / PBM-related data path

What is **not** proven to be board-integrated today:

- `rx_parser`
- `arp_responder`
- `tx_stack`
- `fast_path`
- `packet_dispatcher`

## Practical Impact

This directly limits what can be claimed at board level:

- valid board-level claim:
  - new bitstream programs correctly
  - fingerprint reads back correctly
  - current raw DMA/crypto/security-oriented top path is alive
- invalid claim at this stage:
  - full board ARP request/reply closure
  - full board UDP packet parsing and protocol-stack forwarding closure
  - full external network-path closure from host packet capture

Those protocol-stack items remain simulation-verified RTL features unless and until they are explicitly integrated into the active board top-level.

## Recommended Next Step

Do not waste time trying to force host-side ARP/UDP capture against the current bitstream as if the board already exposed the full network stack.

The next technically honest options are:

1. finish UART board visibility so the current board image has readable software evidence, or
2. integrate the protocol-stack modules into the actual board top-level, then attempt ARP/UDP board closure
