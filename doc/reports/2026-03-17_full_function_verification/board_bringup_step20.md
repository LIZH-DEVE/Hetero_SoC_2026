# Step 20: Board Bring-Up and On-Board Closure Status

Date: 2026-03-18

## Scope

This step executed the practical "board-ready" portion of the closure plan:

- rebuild and publish the authoritative bitstream
- verify the board can be programmed from the authoritative `impl_1` path
- verify on-board fingerprint readback through XSDB
- check whether UART-based application logs are usable
- confirm whether the current top-level actually integrates the network stack modules needed for real ARP/UDP closure

## Authoritative Bitstream

- Bitstream path:
  - `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit`
- Rebuild completed successfully on `2026-03-18 07:36:42`
- SHA256:
  - `DFBFAD2BDF2FD5E5688336C0304CE20AC33207BE1417FA28B979AE56442C6778`
- Published copy hash matches:
  - `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/artifacts/bitstreams/latest/design_1_wrapper.bit`

## XSDB Flow Fixes

The original board scripts were not robust enough for the actual hardware session. The following issues were fixed:

- `xsdb_check_status.tcl`
  - stopped using ambiguous `*Cortex*` target matching
  - now selects `ARM Cortex-A9 MPCore #0`
  - now enables `configparams force-mem-access 1` so PL AXI address `0x43C00008` can be read from XSDB
- `download_bitstream.tcl`
  - stopped using stale target matching
  - made `stop` non-fatal via `catch`
  - added `ps7_init` / `ps7_post_config`
  - added UART1 clock and MIO bring-up after PL programming
- `run_board_smoke.ps1`
  - remained the driver, but became usable only after the Tcl fixes above

## Board-Level Smoke Result

Fresh board run:

- command:
  - `powershell -ExecutionPolicy Bypass -File .\HCS_SOC\run_board_smoke.ps1 -Action program_and_status -XsdbPath D:\Xilinx\Vitis\2024.1\bin\xsdb.bat`
- result:
  - `STATUS = 0xACE00447`
  - `Hardware Fingerprint = 0xACE`
  - `PASS: hardware fingerprint matches 0xACE`

This is direct board evidence that:

- the new authoritative bitstream is actually being programmed
- the PL register map is alive on the board
- the hardware fingerprint path still reads back correctly after the latest RTL integration set

## UART Status

UART is only partially closed.

What was proven:

- the UART electrical/data path is no longer dead
- after the latest XSDB UART bring-up sequence, `COM9` started receiving non-empty data
- direct `UART0` FIFO injection produced no `COM9` output, while `UART1` injection did produce bytes
- UART-related registers on the board changed as expected during bring-up:
  - `UART_CLK_CTRL = 0x00001403`
  - `UART1_BRGR = 0x0000003E`
  - `UART1_BDIV = 0x00000006`
  - `UART1_SR   = 0x0000000A`

What is still not closed:

- captured UART output is still garbled, not readable application logs
- even direct XSDB FIFO injection of test strings did not decode cleanly on the host serial capture

Current judgment:

- UART path is active but baud/clock mapping is still not reliably aligned with host-side decoding
- the active USB-UART path is consistent with `UART1`, not `UART0`
- therefore UART is **not** yet acceptable as board-level acceptance evidence for AES/SM4 test logs

## Network Closure Reality Check

The current board top-level does **not** yet justify full ARP/UDP board-closure claims.

Static integration check showed:

- `dma_subsystem.sv` integrates:
  - `config_packet_auth`
  - `acl_packet_filter`
- current top-level integration evidence did **not** show:
  - `rx_parser`
  - `arp_responder`
  - `tx_stack`
  - `fast_path`
  connected into the actual block-design-backed board top path

That means:

- ARP/UDP module sanity is real at RTL/simulation level
- but full board-level network-chain closure is still blocked by top-level integration scope
- pushing straight to live host ARP/UDP capture now would over-claim what the board image actually contains

## Practical Host-Side Risk Found

Host Ethernet is currently:

- interface: `以太网`
- IPv4: `192.168.1.10/24`

Project network defaults also heavily use:

- `192.168.1.10` / `32'hC0_A8_01_0A`

So if the board image later uses the same default local IP, host and board will collide immediately. This is a real bring-up risk that must be handled before any honest ARP/UDP board test.

## Acceptance Status After Step 20

### Closed with board evidence

- authoritative bitstream rebuild and publish
- on-board bitstream programming from `impl_1`
- on-board hardware fingerprint readback (`0xACE`)

### Closed only with simulation evidence

- ARP minimal loop
- ACL/auth ingress chain
- FastPath behavior
- top-level raw TX `tlast` contract

### Still blocked / not board-accepted

- UART-readable application log capture
- board-level AES/SM4 pass logs through UART
- board-level ARP/UDP external network closure
- board-level validation of auth/ACL behavior from an external traffic source

## Resolution Update On 2026-03-18

The UART portion of this step is now closed by follow-on verification in:

- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/2026-03-17_full_function_verification/uart_boot_log_step22.md`

What changed after this report:

- `main.c` gained a UART1 bootstrap path and FIFO pre-check before startup prints
- UART1 board bring-up was normalized to a preferred `115200` baud configuration
- host-side capture was automated through `capture_uart_boot_log.ps1`
- three board runs produced readable `COM9` logs containing:
  - `BOOT UART1 OK`
  - `STATUS=0xACE00403`
  - `FINGERPRINT=0xACE`
  - readable AES / SM4 / security test output

So these two items are no longer blocked:

- UART-readable application log capture
- board-level AES/SM4 pass logs through UART

## Next Most Defensible Step

Do not pretend the network chain is already board-integrated.

The next practical step should be one of these, in order:

1. close UART baud/host decoding so board application logs become readable again
2. confirm and, if needed, integrate the actual network modules into the board top path
3. only then attempt host-side ARP/UDP packet capture
