# Shadow Mirror P0-P2 And SD Cold-Start Soak Closure

Date:
- `2026-04-02`

Scope:
- `P0` host helper alignment for `UNEXPECTED_REPLY`
- `P1` formal `SD cold-start soak`
- `P2` observability bit-packing in status payload

## Acceptance Image

- Image: `HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror/BOOT.BIN`
- SHA256: `CE4C710DD502F35BED170AC3C22362288505F5CF5817548A52032AD6DEF6856D`

## Local Verification

- Python and release/runtime regression:
  - `111 tests OK`
- PowerShell parse checks:
  - `board_check / acl_check / security_check / soak_check / capture_uart_boot_log` PASS
- Firmware rebuild:
  - app build PASS
  - boot build PASS

## Board Validation After Rebuild

Cold-start board suite:
- `board_check`: PASS
- `ACL`: PASS
- `FastPath`: PASS
- `Security`: PASS
- `Performance`: PASS

Updated board performance capture:
- Capture directory: `doc/reports/board_benchmarks/shadow_mirror_20260402_212652`
- AES avg speedup = `2.765941x`
- SM4 avg speedup = `2.104324x`

Updated observability evidence:
- ACL path reports `last_drop_reason = ACL`
- Replay-triggered security path reports `last_lock_reason = REPLAY_THRESHOLD`
- Locked data-plane rejection reports `last_drop_reason = UNAUTHORIZED`

## SD Cold-Start Soak

Smoke run:
- Capture directory: `doc/reports/board_soak/shadow_mirror_20260402_215550`
- Mode: `sd cold-start soak`
- Duration: `1` minute
- Result: `PASS`

Formal run:
- Capture directory: `doc/reports/board_soak/shadow_mirror_20260402_215701`
- Mode: `sd cold-start soak`
- Duration: `30` minutes
- Result: `PASS`
- Cycles completed: `124`
- AES probes: `124`
- SM4 probes: `124`
- ACL probes: `12`
- Replay probes: `6`
- Final `bind_fail = 0`
- Final `crypto_timeout = 0`
- Final `crypto_fail = 0`

Cold-start evidence mode:
- `boot_evidence_found = true`
- `boot_evidence_mode = control_data_after_manual_power_cycle`

Explanation:
- Real cold power cycles on the current `CP210x` UART chain did not reliably produce a captured boot banner file.
- The soak entry therefore now uses a two-stage evidence model:
  - prefer explicit UART boot evidence when available
  - otherwise require successful post-power-cycle control-plane recovery plus first data-plane success

Observed boundaries:
- no new `shadow compare fail`
- no new `SHADOW_FASTPATH FALLBACK`
- cold-start UART boot capture remained empty in the formal soak run and was recorded as a warning, not a functional failure

## Final Judgment

- `P0` is complete: helper result semantics now align with real board success criteria
- `P1` is complete: formal `SD cold-start soak` is implemented and board-proven
- `P2` is complete: observability bit-packing is implemented, decoded by host tools, and asserted by board checks

Recommended status wording:
- `The current shadow_mirror image is board-proven, performance-proven, security-proven, JTAG-soak-proven, and SD-cold-start-soak-proven on AX7020.`
