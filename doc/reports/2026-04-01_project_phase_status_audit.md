# Project Phase Status Audit

Date:
- `2026-04-01`

Last updated:
- `2026-04-05`

Audit scope:
- Requirements source: `D:\FPGAhanjia\大一寒假\21天硬件安全加速网卡 (1).docx`
- Current engineering scope: `AX7020 UDP Crypto Gateway / Phase C shadow_mirror`
- Current acceptance image: `HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror/BOOT.BIN`

## 1. Audit Baselines

This audit separates two baselines so that current-phase completion is not confused with the original full blueprint.

Baseline A: current approved execution scope
- `AX7020 UDP Crypto Gateway`
- `Phase C shadow_mirror`
- Stage 2 SG proof
- full merge-back acceptance on `xc7z020`
- board security closure and JTAG soak closure

Baseline B: original full `21-day` blueprint
- includes broader goals such as additional security hardening, more complete firewalling, deeper evidence-pack closure, and other stretch items beyond the current accepted scope

## 2. Overall Completion

Baseline A:
- completion estimate: `95%`
- status: `completed for current phase`
- delivery state: `board-proven + performance-proven + security-proven + jtag-soak-proven + sd-cold-start-soak-proven + cold-start-validated`

Baseline B:
- completion estimate: `63%`
- status: `mainline complete, full blueprint not fully closed`

## 3. Completed Core Items

The following are complete against the current phase target:

- `DMA + ring + hardware transport`
- stable multi-block `AES/SM4`
- board performance benchmarking and speedup closure
- `DNA` binding closure
- replay protection
- lightweight self-destruction semantics: detect abnormal condition, lock, and require re-auth
- ACL ingress enforcement
- shadow fastpath board closure
- JTAG day-to-day development flow
- `30` minute JTAG mixed soak
- `SD cold-start soak`
- packed status observability for `last_drop_reason` and `last_lock_reason`

## 4. Hard Evidence Snapshot

Acceptance image:
- `BOOT.BIN` SHA256 = `8D8501A0FD5A59B8511DA88507E20068DFC3D866E7E9CCD1A8AD47F50B2C8A72`

Board performance:
- capture directory: `doc/reports/board_benchmarks/shadow_mirror_20260405_204158`
- AES avg speedup = `2.773757x`
- SM4 avg speedup = `2.102749x`

ACL board result:
- blocked packet increments `acl_drop_count`
- observed board delta: `0 -> 1`

Replay / lock result:
- replay attempts are rejected and counted
- lock clears authorization
- service recovers only after re-authentication

Shadow fastpath result:
- `FASTPATH_HIT_COUNT=2`
- `FASTPATH_FALLBACK_COUNT=0`

JTAG soak result:
- capture directory: `doc/reports/board_soak/shadow_mirror_20260401_224117`
- result = `PASS`
- cycles completed = `128`
- AES probes = `128`
- SM4 probes = `128`
- ACL probes = `12`
- replay probes = `6`
- no observed growth in `bind_fail`, `crypto_timeout`, or `crypto_fail`

SD cold-start soak result:
- report: `doc/reports/2026-04-02_shadow_mirror_p0_p2_and_sd_cold_start_soak_closure.md`
- formal capture directory: `doc/reports/board_soak/shadow_mirror_20260402_215701`
- result = `PASS`
- cycles completed = `124`
- AES probes = `124`
- SM4 probes = `124`
- ACL probes = `12`
- replay probes = `6`
- `boot_evidence_mode = control_data_after_manual_power_cycle`
- no observed growth in `bind_fail`, `crypto_timeout`, or `crypto_fail`

Cold-start post-confirmation result:
- report: `doc/reports/2026-04-02_shadow_mirror_cold_start_post_confirmation.md`
- SD deploy SHA matched the then-current release SHA
- `board_check`: PASS
- `ACL`: PASS
- `FastPath`: PASS
- `Security`: PASS
- `Performance`: PASS
- no new `shadow compare fail`
- no new `SHADOW_FASTPATH FALLBACK`

SD regression recovery result:
- report: `doc/reports/2026-04-05_shadow_mirror_sd_boot_regression_recovery.md`
- current release build reproduces the board-proven `SD` image SHA exactly
- `ping`: PASS
- `hello`: PASS
- `board_check`: PASS
- `ACL`: PASS
- `FastPath`: PASS
- `Security`: PASS
- `Performance`: PASS

## 5. Remaining Work With Highest Priority

Remaining work is now primarily engineering closeout, not core feature completion.

Highest priority:
- synchronize any remaining outward-facing status docs or presentation material to the latest `8D85...` image and `SD regression recovery` result
- optionally improve strict `UART boot-banner` capture under real cold power cycles if boot-banner evidence itself becomes a formal release gate
- define resource-budget redlines for future modifications so the current fit/timing closure is not accidentally regressed

Lower priority, outside the current phase target:
- more complex tamper / JTAG destructive-response logic
- broader ACL / firewall evolution beyond the current accepted closure
- more aggressive zero-copy and deeper throughput optimization
- larger original-blueprint algorithm expansion

## 6. Risks and Boundaries

Resource headroom:
- slice usage remains high at `93.38%`
- current image implements and passes, but future large security or debug additions can re-introduce fit pressure

JTAG soak UART boundary:
- current soak pass does not require UART file creation
- UART remains supplemental unless explicit hard-bad evidence is captured

SD cold-start soak UART boundary:
- the current cold-start soak passed via fallback control/data evidence after manual power cycle
- current `CP210x` capture behavior under real cold power cycles does not reliably yield a boot banner file
- this is a visibility limitation, not a functional correctness failure, under the current acceptance contract

Scope boundary:
- current phase is complete at the engineering-delivery level
- the original full blueprint is intentionally larger than the accepted current-phase target

## 7. Final Judgment

Current phase:
- verdict: `complete`
- completion: `95%`

Original full blueprint:
- verdict: `partially complete`
- completion: `63%`

Recommended status wording:
- `The current Phase C shadow_mirror program is complete for its approved scope and is board-proven, performance-proven, security-proven, JTAG-soak-proven, SD-cold-start-soak-proven, and cold-start-validated on xc7z020.`
