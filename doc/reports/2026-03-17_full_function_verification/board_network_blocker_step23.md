# Step 23: Board-Level Network Blocker in the Active `system` Design

Date: 2026-03-18

## Purpose

This step closes a practical verification question:

Can the current programmed board image honestly support board-level ARP/UDP closure, or are the protocol-stack modules still only simulation-proven RTL?

The answer is now evidence-based: the current active board design cannot provide a real external network path yet.

## Key Conclusion

The programmed top-level is the Vivado block design `system`, and that active design:

- instantiates `dma_subsystem_v2_wrapper`
- exports raw `rx_wr_*` and `tx_axis_*` ports around `dma_subsystem`
- ties `rx_wr_data`, `rx_wr_last`, and `rx_wr_valid` to constant zero in the generated BD netlist
- does not enable PS Ethernet or EMIO Ethernet in `system.bd`
- does not integrate `rx_parser`, `arp_responder`, `tx_stack`, `fast_path`, or `packet_dispatcher` into the active board top

Because of that, the current board image cannot truthfully be used for board-level ARP request/reply or UDP packet-path closure, regardless of the fact that those modules now pass simulation.

## Evidence

### 1. The active BD wrapper is `system_dma_subsystem_v2_wra_0_0`

Generated wrapper:

- [system_dma_subsystem_v2_wra_0_0.v](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.gen/sources_1/bd/system/ip/system_dma_subsystem_v2_wra_0_0/synth/system_dma_subsystem_v2_wra_0_0.v)

Relevant lines:

- line 58: `module system_dma_subsystem_v2_wra_0_0`
- line 189: `input wire rx_wr_valid;`
- line 190: `input wire [31 : 0] rx_wr_data;`
- line 191: `input wire rx_wr_last;`
- line 194: `output wire [31 : 0] tx_axis_tdata;`
- line 198: `output wire tx_axis_tlast;`
- line 200: `output wire [3 : 0] tx_axis_tkeep;`

This confirms the active BD-facing IP is a raw ingress/egress wrapper around `dma_subsystem`, not a protocol-stack top.

### 2. The handwritten wrapper matches that raw-stream contract

Source wrapper:

- [dma_subsystem_v2_wrapper.v](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/dma_subsystem_v2_wrapper.v)

Relevant lines:

- line 3: `module dma_subsystem_v2_wrapper`
- line 31: stream section comment
- line 32: `input  wire                   rx_wr_valid,`
- line 33: `input  wire [31:0]            rx_wr_data,`
- line 34: `input  wire                   rx_wr_last,`
- line 36: `output wire [31:0]            tx_axis_tdata,`
- line 37: `output wire                   tx_axis_tvalid,`
- line 38: `output wire                   tx_axis_tlast,`
- line 39: `output wire [3:0]             tx_axis_tkeep,`
- line 109: instantiates `dma_subsystem`

Again, this is a raw data-stream wrapper, not a board top with Ethernet ingress or a complete protocol stack.

### 3. `dma_subsystem` integrates ingress security, not the network stack

Source:

- [dma_subsystem.sv](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/top/dma_subsystem.sv)

Positive instantiation hits:

- line 439: `config_packet_auth u_cfg_auth`
- line 529: `acl_packet_filter u_acl_filter`

No instantiation hits were found for:

- `rx_parser`
- `arp_responder`
- `tx_stack`
- `fast_path`
- `packet_dispatcher`

This means the board-integrated data path currently includes the security ingress chain, crypto, PBM, and DMA infrastructure, but not the higher-level packet parser / responder / forwarding stack.

### 4. The active generated BD ties ingress stream inputs off to zero

Generated top-level netlist:

- [system.v](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.gen/sources_1/bd/system/sim/system.v)

Critical lines:

- line 1709: `system_dma_subsystem_v2_wra_0_0 dma_subsystem_v2_wra_0`
- line 1766: `.rx_wr_data({1'b0, ... ,1'b0})`
- line 1767: `.rx_wr_last(1'b0)`
- line 1768: `.rx_wr_valid(1'b0)`

This is the strongest board-level blocker. Even if `dma_subsystem` were otherwise healthy, the active board design is not feeding any live ingress stream into it.

### 5. PS Ethernet and EMIO Ethernet are disabled in `system.bd`

BD source:

- [system.bd](D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.srcs/sources_1/bd/system/system.bd)

Relevant properties:

- line 375: `PCW_ENET0_PERIPHERAL_ENABLE`
- line 376: `"value": "0"`
- line 381: `PCW_ENET1_PERIPHERAL_ENABLE`
- line 382: `"value": "0"`
- line 435: `PCW_EN_EMIO_ENET0`
- line 436: `"value": "0"`
- line 438: `PCW_EN_EMIO_ENET1`
- line 439: `"value": "0"`
- line 498: `PCW_EN_ENET0`
- line 499: `"value": "0"`
- line 501: `PCW_EN_ENET1`
- line 502: `"value": "0"`

So the current block design does not expose a PS Ethernet path either. There is no honest basis for claiming a real host-to-board packet ingress path in the active image.

## What the Board Image Can Honestly Claim Today

Board-proven today:

- bitstream rebuild / publish / program flow works
- hardware fingerprint `0xACE` is present on the board
- UART1 boot logs are readable at `115200`
- crypto smoke and status visibility are live on hardware
- the active top exports a raw `tx_axis_*` stream from the crypto/DMA side

Simulation-proven only today:

- `rx_parser`
- `arp_responder`
- `tx_stack`
- `fast_path`
- `packet_dispatcher`
- ARP minimum closure
- protocol-level UDP parsing / forwarding

## Practical Impact

This removes a false next step.

It is not technically honest to spend more time trying to capture ARP request/reply or UDP closure on the current board image, because:

- the active board top does not consume external ingress packets
- the active board design has no enabled Ethernet path
- the protocol-stack modules are not yet integrated into the active board top

## Recommended Next Step

There are only two technically coherent options from here:

1. keep the current board image as a crypto/DMA/security bring-up vehicle and stop claiming board-level network closure, or
2. build a new board top or modify `system.bd` so that a real ingress source and the protocol-stack modules are actually integrated before attempting ARP/UDP board validation

The recommended option is `2`, because the current blocker is architectural integration, not module correctness.
