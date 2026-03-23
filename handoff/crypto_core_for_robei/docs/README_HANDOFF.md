# Crypto Core Handoff For Robei

## What this package is
- This package is a **Robei-oriented crypto IP handoff**, not a full AX7020 SoC project.
- The main import path for Robei is:
  - `rtl_robei_ready/`
- The main top module for Robei is:
  - `crypto_robei_top`

## What to import into Robei
- Import **only** the Verilog files under `rtl_robei_ready/`.
- Start from `crypto_robei_top`.
- Do not start from AXI-Lite wrappers.

## Main top interface
`crypto_robei_top` exposes only 32-bit word interfaces:
- `key_word[31:0]`
- `key_word_valid`
- `key_word_last`
- `din_word[31:0]`
- `din_word_valid`
- `din_word_last`
- `start`
- `dout_word[31:0]`
- `dout_word_valid`
- `dout_word_last`
- `busy`
- `done`

### Word ordering
- Data words are loaded in order and packed as:
  - first word -> bits `[127:96]`
  - second word -> bits `[95:64]`
  - third word -> bits `[63:32]`
  - fourth word -> bits `[31:0]`
- AES-128 and SM4 keys use 4 words.
- AES-256 keys use 8 words.
- Assert `*_word_last` on the final word of the transaction.

## Recommended Robei integration order
1. Import `rtl_robei_ready/`.
2. Instantiate `crypto_robei_top`.
3. Drive the 32-bit key path.
4. Drive the 32-bit data path.
5. Pulse `start` after key and data have been loaded.
6. Observe `dout_word_valid` / `dout_word_last`.
7. Only after that, connect an external physical stimulus layer such as UART, buttons, switches, or a small controller state machine.

## Important exclusions
- This package does **not** include AX7020 platform files, FSBL, BOOT.BIN, JTAG fixes, or Ethernet bring-up.
- Do **not** expect DMA or network-chain integration instructions here.

## Reference-only content
- `rtl_vivado_reference/` contains the original Vivado-oriented RTL, including SystemVerilog source.
- `tb_vivado_only/` contains SystemVerilog testbenches for Vivado/Modelsim cross-checking only.
- `scripts_vivado_only/` contains `.ps1` and `.tcl` scripts for Vivado-only workflows.

## Warnings
- WARNING: Do not import `.sv` testbench files into a Robei project.
- WARNING: Do not use the AXI-Lite slave as the default Robei integration entry point.
- WARNING: The Robei handoff path is block-oriented. The simplified `crypto_engine.v` in `rtl_robei_ready/` is intended for ECB-style single-block execution, not the original SoC-side control path.
