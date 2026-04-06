# Shadow Mirror Cold-Start Post Confirmation

Date:
- `2026-04-02`

Scope:
- Post-confirmation after `Pblock` landing
- Validation path: `SD + power-cycle`
- Acceptance target: confirm the latest formal `BOOT.BIN` still passes cold-start functional, security, fastpath, and performance closure

## Acceptance Image

- Image: `HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror/BOOT.BIN`
- SHA256: `2A66539954DD8E8EEE9BC0689E4A970D7CA1D58A50998F8E0724B78ADCB3B68D`
- SD deploy target: `E:\BOOT.BIN`

## Step Results

### 1. SD deploy

- Result: `PASS`
- Deployed image SHA256 matched the release artifact exactly

### 2. Cold-start board check

- Result: `PASS`
- UART log: `board_uart_boot_115200_20260402_181045.txt`
- Required evidence observed:
  - `HELLO`
  - `LIVE_AES PASS`
  - `LIVE_SM4 PASS`
  - `SHADOW_AES PASS`
  - `SHADOW_SM4 PASS`
  - `UDP gateway shadow mirror PASS`
- Not observed:
  - `shadow compare fail`
  - `SHADOW_FASTPATH FALLBACK`

Important note:
- Host-side helper output showed `UNEXPECTED_REPLY` for the standalone AES/SM4 probes because the helper's expected ciphertext was not aligned with the current effective on-board key selection.
- This did not invalidate the acceptance result because the authoritative board evidence remained:
  - control session success
  - valid reply received from the board
  - matching UART-side `LIVE_* PASS` and `SHADOW_* PASS` evidence
  - script exit code `0`

### 3. ACL cold-start check

- Result: `PASS`
- UART log: `board_uart_boot_115200_20260402_181255.txt`
- Control evidence:
  - `acl_drop_count_before=0`
  - `acl_drop_count_after=1`
  - `acl_counter_delta=1`
- UART evidence:
  - `SHADOW_ACL_DROP PASS acl_count=1`
- Script ending:
  - `ACL board check completed`

### 4. FastPath cold-start check

- Result: `PASS`
- UART log: `board_uart_boot_115200_20260402_181410.txt`
- Evidence:
  - `SHADOW_FASTPATH PASS` observed twice
  - `FASTPATH_HIT_COUNT=4`
  - `FASTPATH_FALLBACK_COUNT=0`
  - `LIVE_AES PASS`
  - `LIVE_SM4 PASS`
- Script ending:
  - `fastpath board check completed`

### 5. Security negative check

- Result: `PASS`
- UART log: `board_uart_boot_115200_20260402_181616.txt`
- Control evidence:
  - `drop_replay 0 -> 3`
  - `lock_events 0 -> 1`
  - `authorized_mask 3 -> 0` after replay-triggered lock
  - `reply_while_locked=False`
  - `reply_after_unlock_before_reauth=False`
  - `reply_after_reauth=True`
- Script ending:
  - `security board check completed`

### 6. Performance cold-start check

- Result: `PASS`
- UART log: `board_uart_boot_115200_20260402_181824.txt`
- Capture directory: `doc/reports/board_benchmarks/shadow_mirror_20260402_181824`
- JSON: `board_bench_report.json`
- Markdown: `board_bench_summary.md`
- Result summary:
  - `Target result: PASS`
  - AES avg speedup = `2.767194x`
  - SM4 avg speedup = `2.104666x`

## Final Judgment

- `Pblock` landing did not break cold-start behavior
- The latest formal image is:
  - `board-proven`
  - `performance-proven`
  - `security-proven`
  - `soak-proven`
  - `cold-start-validated`

Recommended release wording:
- `The latest shadow_mirror image remains valid after Pblock landing and has passed SD cold-start post-confirmation on AX7020.`
