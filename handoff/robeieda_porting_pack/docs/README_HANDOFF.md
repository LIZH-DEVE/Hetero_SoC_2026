# AX7020 Non-DMA UDP Crypto Gateway Handoff

## Purpose
- This handoff package documents the current software-contract baseline for the AX7020 UDP crypto gateway.
- It is intended for:
  - board-side acceptance once the board is available again
  - teammate migration to `robeieda`
  - later DMA replacement without changing external protocol semantics

## Non-negotiable source of truth
- The Python host-side acceptance scripts are the only final oracle for this protocol baseline.
- If `robeieda` board output differs from the Python Golden Vector, treat the board-side implementation as wrong first:
  - logic bug
  - endianness bug
  - state-machine bug
  - serialization bug
- Do not modify Python tests to make a broken board implementation pass.
- Host and board may only be changed together when the protocol itself is intentionally upgraded. Porting is not a protocol-upgrade phase.

## Current baseline
- Stable hardware line is unchanged:
  - official `06_net_test` `fsbl.elf`
  - backup working `design_1_wrapper.bit`
  - current `ws_2` application ELF
- Algorithms remain ECB-only:
  - UDP `4660` = AES-128 ECB encrypt
  - UDP `4661` = SM4 encrypt
- Control plane:
  - UDP `4662`
- Data-plane payload contract:
  - `0 < len <= 1472`
  - `len % 16 == 0`
  - payload is raw block data only
  - no session header, no replay fields, no DNA field in data packets

## Security-control additions in this baseline
- Source-IP-scoped control session on `4662`
- Authorization gate before data-plane use
- Placeholder DNA binding:
  - `binding_id = 0x41583702`
- Control-plane replay protection:
  - `session_id + seq_id`
  - 32-entry sliding replay window
- Lightweight self-destruct:
  - software lock only
  - zero effective keys
  - unlock only by control-plane `UNLOCK` or reboot

## Current internal limits
- Session slots:
  - `4`
- Request queue depth:
  - `4`
- Control payload max:
  - `64` bytes

## Source of truth
- Firmware:
  - `HCS_SOC/vitis_2023_udp_gateway_ws_2/ax7020_udp_gateway_app/src/udp_crypto_gateway.c`
- Control client:
  - `HCS_SOC/udp_crypto_control.py`
- Data-path sender:
  - `HCS_SOC/send_udp_crypto_test.py`
- Data regression:
  - `HCS_SOC/run_udp_crypto_length_regression.py`
- Control regression:
  - `HCS_SOC/run_udp_crypto_control_regression.py`
- One-click acceptance:
  - `HCS_SOC/run_udp_crypto_acceptance.py`
- Acceptance report:
  - `HCS_SOC/run_udp_crypto_acceptance_report.py`

## This handoff package
- `CONTROL_PROTOCOL.md`
  - fixed control header, message types, status codes, payload formats
- `BOARD_ACCEPTANCE.md`
  - board-side validation sequence and pass criteria
- `ROBEIEDA_PORTING_NOTES.md`
  - what must stay stable for migration and later DMA replacement
- `ROBEIEDA_BRINGUP_CHECKLIST.md`
  - required implementation order:
    - `UDP Echo -> Header Parser -> HELLO -> SET_KEY -> Replay -> Lock/Unlock -> Data Plane -> BENCH`

## Explicit non-goals
- No DMA, ring, or hardware data mover yet
- No CBC
- No real hardware DNA readout yet
- No tamper/JTAG self-destruct path
- No new board-side claims beyond previously validated ECB data path
