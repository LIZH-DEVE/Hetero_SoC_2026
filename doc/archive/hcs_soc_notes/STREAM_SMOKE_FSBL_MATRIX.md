# Stream-Smoke FSBL Root-Cause Matrix

This document freezes the current Phase 3 evidence matrix and the current
officialization gate for the dedicated stream-smoke image.

## Current baseline and official matrix

1. `stream-smoke FSBL + no-bit + stream-smoke app`
   - current result: pass
   - conclusion: stream-smoke FSBL + app handoff is alive without PL configuration

2. `design1 FSBL + stream-smoke bit + design1 UART app`
   - current result: pass
   - conclusion: stream-smoke bit alone does not kill board bring-up

3. `design1 FSBL + stream-smoke bit + stream-smoke app`
   - current result: pass
   - conclusion: stream-smoke app + bitstream + data path are valid on hardware

4. `stream-smoke FSBL + stream-smoke bit + stream-smoke app`
   - historical result: fail on the original dedicated official chain
   - current state: the official builder now injects a delay-only stabilization in
     the dedicated FSBL with-bit handoff path
   - conclusion: the dedicated FSBL remains the only remaining officialization
     variable, but the official line is no longer an unmodified failing reference

## Dedicated-FSBL-only control and perturbation matrix

The dedicated with-bit path now uses five repo-owned images:

1. `official dedicated stream-smoke image`
   - status: experimental / non-gating
   - role: official candidate image for Phase 3 officialization
   - current builder behavior:
     - no UART breadcrumbs
     - keep `ps7_post_config()`
     - add exactly two fixed delay spins in the with-bit `FsblHandoff()` path
   - promotion rule:
     - remains experimental until it passes 3 consecutive cold boots on hardware

2. `corrected trace`
   - status: board-proven control image
   - role: known-good dedicated-FSBL-only control
   - current board result:
     - `AFTER_PS7_INIT`
     - `BEFORE_PCAP_LOAD`
     - `AFTER_PCAP_LOAD`
     - `BEFORE_POST_CONFIG`
     - `AFTER_POST_CONFIG`
     - `BEFORE_HANDOFF`
     - `DMA stream smoke PASS`

3. `handofflite`
   - status: board-proven minimal UART-perturbation image
   - role: keep only:
     - `FSBL_DIAG BEFORE_POST_CONFIG`
     - `FSBL_DIAG AFTER_POST_CONFIG`
     - `FSBL_DIAG BEFORE_HANDOFF`
   - current board result:
     - `DMA stream smoke PASS`

4. `handoffdelay`
   - status: board-proven minimal timing-perturbation image
   - role: no new UART breadcrumbs; only two fixed delay spins:
     - after `ps7_post_config()`
     - before `FsblHookBeforeHandoff()`
   - current board result:
     - `DMA stream smoke PASS`

5. `nopostcfg`
   - status: refutation image only
   - role: prove that skipping `ps7_post_config()` is not an acceptable fix
   - current board result:
     - reaches the app banner
     - does not complete `DMA stream smoke PASS`

## Root-cause boundary

Allowed investigation scope:
- FSBL generation source and generated FSBL project content
- BSP / linker / specs differences between design1 FSBL and stream-smoke FSBL
- bitstream download / PL init / handoff behavior before app control reaches `main()`
- memory / cache / peripheral state immediately before app handoff

Out of scope for this failure:
- stream-smoke bitstream alone
- stream-smoke app alone
- stream data path RTL alone
- gateway integration
- full `system_wrapper`

## Initial dedicated-FSBL delta scan

The first targeted diff between the passing design1 FSBL chain and the failing dedicated
stream-smoke FSBL chain shows:

- `ps7_init.c` and `ps7_init.h` are identical between the two generated FSBL workspaces.
- `lscript.ld` is identical between the two generated FSBL workspaces.
- `Xilinx.spec` is identical between the two generated FSBL workspaces.
- `fsbl.elf` differs.
- `ps7_parameters.xml` differs.
- `zynq_fsbl_bsp` `xparameters.h` differs.
- `zynq_fsbl_bsp` `libxil.a` differs.

Current strongest concrete deltas:

- In the generated `ps7_parameters.xml`, the passing design1 FSBL path carries
  `PCW_USE_S_AXI_HP0 = 0`, while the dedicated stream-smoke FSBL path carries
  `PCW_USE_S_AXI_HP0 = 1`.
- The generated `zynq_fsbl_bsp` `xparameters.h` also differs at the peripheral map level:
  the design1 FSBL path exposes `CRYPTO_ACCEL_AXI_0`, while the dedicated stream-smoke FSBL path
  exposes `DMA_STREAM_SMOKE_SUBSYSTEM_0`.

Current interpretation:

- The problem is not currently explained by generic FSBL source code, linker script, or
  top-level specs drift.
- The problem is still concentrated in platform-export metadata feeding the dedicated
  stream-smoke FSBL generation path, but the current evidence does not support a simplistic
  `HP0 on/off` explanation by itself.
- The remaining investigation target is the dedicated FSBL's with-bit PL configuration /
  handoff state, not the stream-smoke app or data path.

## Current policy

- Temporary board-proven Phase 3 baseline:
  - `design1 fsbl.elf + stream_smoke_dma_wrapper.bit + ax7020_dma_raw_copy_stream_smoke_app.elf`
- Current temporary baseline hash:
  - `8F137D1A03F093A49FC6BCFB98EABDB5060687CC18CB8CC6F0FA664215D8D9CA`
- Dedicated stream-smoke official image remains experimental / non-gating
- The official builder now carries the delay-only stabilization, but that does not
  make the image board-proven yet
- Gateway stays blocked until the dedicated stream-smoke official image matches the
  temporary baseline UART pass log for 3 consecutive cold boots

## Dedicated-FSBL-only diagnostics

To isolate the dedicated with-bit failure without perturbing the passing app or bitstream,
the dedicated stream-smoke line now grows two diagnostic-only variants:

1. `FSBL trace image`
   - composition: dedicated stream-smoke FSBL + stream-smoke bit + stream-smoke app
   - purpose: leave UART breadcrumbs on the with-bit path and show how far dedicated FSBL runs
   - first trusted breadcrumb is fixed to:
     - `FSBL_DIAG AFTER_PS7_INIT`
   - this diagnostic line must never use:
     - `FSBL_DIAG ENTER_MAIN`
   - every breadcrumb must use `xil_printf(...\r\n)` and a TXEMPTY drain

2. `FSBL no-post-config image`
   - composition: dedicated stream-smoke FSBL + stream-smoke bit + stream-smoke app
   - purpose: skip `ps7_post_config()` only on the with-bit path and determine whether the
     remaining blocker is in the post-config / handoff window
   - this line keeps the same post-`ps7_init()` breadcrumb policy as the trace image

3. `FSBL handofflite image`
   - composition: dedicated stream-smoke FSBL + stream-smoke bit + stream-smoke app
   - purpose: keep only the handoff-window UART perturbation and determine whether that smaller
     breadcrumb set is sufficient to keep the dedicated with-bit path alive
   - this line must not emit:
     - `FSBL_DIAG AFTER_PS7_INIT`
     - `FSBL_DIAG BEFORE_PCAP_LOAD`
     - `FSBL_DIAG AFTER_PCAP_LOAD`

4. `FSBL handoffdelay image`
   - composition: dedicated stream-smoke FSBL + stream-smoke bit + stream-smoke app
   - purpose: remove UART side effects and keep only two fixed delay-spin perturbations in the
     with-bit handoff path
   - this line must not emit any new `FSBL_DIAG ...` breadcrumbs

Interpretation policy for the dedicated-only diagnostics:

- If trace output never reaches `FSBL_DIAG AFTER_PCAP_LOAD`, the blocker is still before or in
  bitstream download.
- If trace output reaches `FSBL_DIAG BEFORE_POST_CONFIG` and then dies, the blocker is inside
  `ps7_post_config()` or its immediate side effects.
- If trace output reaches `FSBL_DIAG AFTER_POST_CONFIG` and then dies, the blocker is after
  post-config but before app handoff.
- If the no-post-config image reaches the same board-pass UART log as the temporary Phase 3
  baseline, the blocker would be confirmed to lie in the dedicated FSBL post-config / with-bit
  handoff window.
- Current board evidence instead shows:
  - `nopostcfg` does not complete the stream-smoke app
  - `ps7_post_config()` must be retained
- If the handoffdelay image reaches the same board-pass UART log as the temporary Phase 3
  baseline, the remaining blocker is primarily time-window sensitivity in the with-bit
  `post_config -> handoff` window.
- If the handofflite image passes but handoffdelay fails, the remaining perturbation is not pure
  delay; UART / drain or broader bus activity is still a required part of the workaround.
- Current board evidence now shows:
  - `corrected trace` passes
  - `handofflite` passes
  - `handoffdelay` passes
  - therefore early `AFTER_PS7_INIT / PCAP_LOAD` breadcrumbs are not required
  - UART output is not required either
  - the remaining officialization question is only whether the stabilized official image is
    repeatable across 3 consecutive cold boots
