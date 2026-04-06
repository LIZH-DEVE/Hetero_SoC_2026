# AX7020 Repo-Owned Board Images

This document defines the board-test order for repo-owned images.

## Board-test order

Always test in this order:

1. `ax7020_vendor_ps_uart_baseline`
2. `ax7020_repo_design1_uart_baseline`
3. `ax7020_dma_raw_copy_smoke`
4. `ax7020_dma_raw_copy_mvp`
5. `ax7020_dma_raw_copy_stream_smoke`
6. `ax7020_dma_gateway_hybrid_smoke`

Do not skip levels. If one level fails, stop and fall back to the previous known-good level.

## Hard constraints

- Board startup truth source: vendor `ps_uart`
- Fresh FSBL rule:
  - Any repo-owned board image must generate `fsbl.elf` from the current Vivado project's freshly exported `.xsa`
  - Do not copy `fsbl.elf` from old workspaces or vendor directories
- Clean BIF rule:
  - `[bootloader] fsbl.elf`
  - `bitstream`
  - `app.elf`
  - No extra undeclared segments

- Raw-copy smoke contract:
  - `MM2S -> AXIS FIFO -> S2MM`
  - FIFO must preserve `TLAST`
  - destination buffers must be 32-byte aligned
  - transfer length must be a multiple of 32 bytes
  - `invalidate(dst)` must happen only after CSW completion
  - FIFO reset must be tied to DMA soft reset

## Repo-owned `design_1` UART baseline

- Output:
  - `HCS_SOC\sd_boot\ax7020_repo_design1_uart_baseline\BOOT.BIN`
- Build entry:
  - `HCS_SOC\build_ax7020_repo_design1_uart_baseline.ps1`
- Deploy entry:
  - `HCS_SOC\deploy_ax7020_repo_design1_uart_baseline_to_sd.ps1`
- Fresh source chain:
  - Vivado project: `HCS_SOC.xpr`
  - XSA export: `design_1_wrapper.xsa`
  - FSBL source: fresh XSCT platform generated from that XSA
  - App source: `ax7020_repo_design1_uart_baseline_app`
- Current timing status:
  - `design_1_wrapper` is timing-clean and is accepted as the repo-owned startup baseline
  - Current post-route summary:
    - `WNS = +4.117ns`
    - `TNS = 0`
    - `WHS = +0.020ns`
    - `THS = 0`

Expected UART text:

```text
REPO DESIGN1 UART BASELINE
UART1 OK
FRESH_XSA_FSBL_CHAIN
REPO_HEARTBEAT 0
```

## Repo-owned `system_wrapper` DMA smoke

- Output:
  - `HCS_SOC\sd_boot\ax7020_dma_mvp_smoke_system\BOOT.BIN`
- Build entry:
  - `HCS_SOC\build_ax7020_dma_mvp_smoke_full.ps1`
- Deploy entry:
  - `HCS_SOC\deploy_ax7020_dma_mvp_smoke_to_sd.ps1`
- Fresh source chain:
  - Vivado project: `HCS_SOC.xpr`
  - system rebuild: `rebuild_system_stage1.ps1`
  - XSA export: `system_wrapper.xsa`
  - FSBL source: fresh XSCT platform generated from that XSA
  - App source: `ax7020_dma_mvp_smoke_app`
- Timing triage/build gate:
  - `HCS_SOC\invoke_vivado_timing_triage.ps1`
  - `HCS_SOC\read_vivado_timing_summary.ps1`
  - Routed DCP:
    - `HCS_SOC\HCS_SOC.runs\impl_1\system_wrapper_routed.dcp`
  - DMA BOOT.BIN may be generated and deployed only when:
    - `WNS >= 0`
    - `TNS = 0`
    - setup failing endpoints = `0`
    - hold failing endpoints = `0`
- Current status:
  - `system_wrapper` is timing-blocked and not board-eligible
  - Current routed summary:
    - `WNS = -1.521ns`
    - `TNS = -989.432ns`
    - setup failing endpoints = `1107`
    - `WHS = +0.043ns`
    - `THS = 0`

Current physical triage facts from routed DCP:
- Clock interaction currently shows one dominant synchronous path group:
  - `clk_fpga_0 -> clk_fpga_0`
- The current failure is not dominated by a broad multi-clock collapse.
- Worst path is concentrated in:
  - `u_network_stage1`
  - `u_tx_stack`
  - `txcap_data_mem_reg[*]`
- `report_design_analysis` shows the worst 1000 paths are dominated by deep logic:
  - logic levels `21-24` on most failing endpoints
- `report_high_fanout_nets` shows a very large reset fanout in `u_crypto_bridge`, but the top violating path itself is still the `u_network_stage1` transmit datapath.
- Required convergence workflow:
  - Follow `HCS_SOC\SYSTEM_WRAPPER_TIMING_GATE.md`
  - Do not start with blind RTL edits before routed-DCP triage

This image is not part of the supported board-test order until timing is clean.

## Repo-owned raw-copy DMA smoke

- Output:
  - `HCS_SOC\sd_boot\ax7020_dma_raw_copy_smoke\BOOT.BIN`
- Build entry:
  - `HCS_SOC\build_ax7020_dma_raw_copy_smoke_boot.ps1`
- Deploy entry:
  - `HCS_SOC\deploy_ax7020_dma_raw_copy_smoke_to_sd.ps1`
- Fresh source chain:
  - Vivado project: `HCS_SOC.xpr`
  - XSA export: fresh from the current Vivado project
  - FSBL source: fresh XSCT platform generated from that XSA
  - App source: raw-copy smoke app
- Raw-copy contract:
  - `MM2S -> AXIS FIFO -> S2MM`
  - FIFO must preserve `TLAST`
  - destination buffers must be 32-byte aligned
  - transfer length must be a multiple of 32 bytes
  - destination invalidate and `dsb()` come after CSW completion
  - FIFO reset is tied to DMA soft reset
- Current status:
  - this is the first board-eligible low-LUT DMA path
  - it must stay below the full `system_wrapper` timing/area risk envelope
  - current board-proven rollback image hash:
    - `44B63D346F2AEB95973DB13476E7D8B00738E64D1C94D4040A62FA0AC86BD23B`
- Root cause that previously blocked this image:
  - raw-copy XSA export applied vendor PS config and silently disabled `S_AXI_HP0`
  - symptom:
    - AXI-Lite CSR path worked
    - descriptor fetch / DDR payload / CSW writeback stalled
    - board logs stuck at `WAIT_CSW` with `OWNER=1`
  - permanent fix:
    - in `export_raw_copy_dma_xsa.tcl`, re-enable and reconnect `S_AXI_HP0` after `set_ps_config`
    - keep this as a release gate for any future raw-copy platform rebuild
- Fixed board-test gate:
  - this image is step 3 in the only supported board-test sequence
  - do not deploy or judge it before:
    - step 1 `ax7020_vendor_ps_uart_baseline` passes with repeated `Hello ALINX!`
    - step 2 `ax7020_repo_design1_uart_baseline` passes with the repo UART banner
  - do not advance to `ax7020_dma_mvp_smoke_system` until this image passes
  - do not advance to `ax7020_dma_raw_copy_mvp` until this image passes
- Phase 2/3 hard defaults frozen from the passing raw-copy baseline:
  - `FCLK0 = 50MHz`
  - IRQ coalescing default = `8` completions or `5000 cycles (100us @ 50MHz)`
  - ring size minimum = `2`
  - software must always keep one slot open in the ring
  - `next_tail == hw_head` means ring full and submit must backpressure instead of overwriting descriptors

Expected UART text for a board pass:

```text
DMA raw-copy smoke image
RAWCOPY_STAGE INIT
RAWCOPY_STAGE RESET
RAWCOPY_STAGE SUBMIT
RAWCOPY_STAGE WAIT_CSW
  CSW=0x...
RAWCOPY_STAGE INVALIDATE_DST
RAWCOPY_STAGE COMPARE
DMA raw-copy smoke PASS
```

Board fail criteria:

- any `DMA raw-copy smoke FAIL`
- missing `DMA raw-copy smoke PASS`
- missing `RAWCOPY_STAGE WAIT_CSW`
- missing CSW status line after `RAWCOPY_STAGE WAIT_CSW`

## Repo-owned raw-copy DMA MVP

- Output:
  - `HCS_SOC\sd_boot\ax7020_dma_raw_copy_mvp\BOOT.BIN`
- Build entry:
  - `HCS_SOC\build_ax7020_dma_raw_copy_mvp_boot.ps1`
- Deploy entry:
  - `HCS_SOC\deploy_ax7020_dma_raw_copy_mvp_to_sd.ps1`
- Current status:
  - this is the board-proven Phase 2 baseline
  - validates multi-descriptor polling, ring-full backpressure, and IRQ count/timeout paths
- Fixed board-test gate:
  - this image is step 4 in the supported board-test sequence
  - do not advance to Phase 3 until this image passes

Expected UART text:

```text
DMA raw-copy MVP image
MVP_STAGE RING_FILL_QUIESCED
MVP_STAGE RING_FULL_EXPECT submit rc[3]=-5
MVP_IRQ_COUNT status=0x00000001 rc=1
MVP_IRQ_TIMEOUT status=0x00000001 rc=1
DMA raw-copy MVP PASS
```

## Phase 3 Temporary Stream-Smoke Baseline

- Output:
  - `HCS_SOC\sd_boot\ax7020_design1fsbl_stream_smoke_app\BOOT.BIN`
- Build entry:
  - `HCS_SOC\build_ax7020_design1fsbl_stream_smoke_app_boot.ps1`
- Deploy entry:
  - `HCS_SOC\deploy_ax7020_design1fsbl_stream_smoke_app_to_sd.ps1`
- Current status:
  - this is the fallback Phase 3 baseline
  - composition is fixed:
    - `design1 fsbl.elf`
    - `stream_smoke_dma_wrapper.bit`
    - `ax7020_dma_raw_copy_stream_smoke_app.elf`
  - current board-proven image hash:
    - `8F137D1A03F093A49FC6BCFB98EABDB5060687CC18CB8CC6F0FA664215D8D9CA`
- Fixed board-test gate:
  - keep this image as fallback only
  - do not use it as the normal Phase 3 entry image once the official stream-smoke image is available

Expected UART text:

```text
DMA stream smoke image
STREAM_STAGE EXACT_FIT PASS actual_len=1024
STREAM_STAGE SHORT PASS actual_len=64
STREAM_STAGE OVERFLOW PASS actual_len=64
DMA stream smoke PASS
```

## Dedicated stream-smoke official image

- Output:
  - `HCS_SOC\sd_boot\ax7020_dma_raw_copy_stream_smoke\BOOT.BIN`
- Build entry:
  - `HCS_SOC\build_ax7020_dma_raw_copy_stream_smoke_boot.ps1`
- Deploy entry:
  - `HCS_SOC\deploy_ax7020_dma_raw_copy_stream_smoke_to_sd.ps1`
- Current status:
  - board-proven dedicated Phase 3 stream-smoke image
  - official builder now applies a delay-only FSBL stabilization in the with-bit
    `FsblHandoff()` path
  - board evidence on `2026-03-27`:
    - 3 consecutive cold boots reached `DMA stream smoke PASS`
  - current official image hash:
    - `91EDCE39C4198167C54192A7520DA63C17B097170EAED6D1478C1A90B200EEFA`
- Gate:
  - this image is step 5 in the supported board-test sequence
  - use this image as the normal Phase 3 board entry
  - if a future rebuild regresses, fall back to `ax7020_design1fsbl_stream_smoke_app`

Expected UART text:

```text
DMA stream smoke image
STREAM_STAGE EXACT_FIT PASS actual_len=1024
STREAM_STAGE SHORT PASS actual_len=64
STREAM_STAGE OVERFLOW PASS actual_len=64
DMA stream smoke PASS
```

## Hybrid gateway smoke

- Output:
  - `HCS_SOC\sd_boot\ax7020_dma_gateway_hybrid_smoke\BOOT.BIN`
- Build entry:
  - `HCS_SOC\build_ax7020_dma_gateway_hybrid_smoke_boot.ps1`
- Deploy entry:
  - `HCS_SOC\deploy_ax7020_dma_gateway_hybrid_smoke_to_sd.ps1`
- Current status:
  - design1-level hybrid smoke line
  - board-proven Phase A hybrid gateway smoke line
  - phase-A scope only:
    - `network/stage1 -> classifier -> DMA v2 stream -> DDR`
    - polling only
    - no live gateway cutover
  - board evidence on `2026-03-28`:
    - `EXACT_FIT PASS`
    - `SHORT PASS`
    - `OVERFLOW PASS`
    - `WRONG_PORT PASS`
    - `UNALIGNED_REJECT PASS`
    - `DMA gateway hybrid smoke PASS`
  - current board-proven image hash:
    - `C85DDC649E523FB03863CB2B9C842E434E173EE546BDB1FCADC56EB467507AD3`
  - ingress contracts frozen:
    - wrong-port packets must be dropped in hardware before DMA ingress
    - unaligned payload lengths must be rejected before injection and defensively dropped in hardware if observed
  - control CSR observability:
    - `WRAP_REG_DROP_WRONG_PORT_COUNT = 0xCC`
    - `WRAP_REG_DROP_UNALIGNED_COUNT = 0xD0`
- Gate:
  - this image is step 6 in the supported board-test sequence
  - use this image as the normal hybrid pre-integration board entry
  - do not advance to any live gateway cutover until the gateway backend split is also board-ready

Expected UART text:

```text
DMA gateway hybrid smoke image
EXACT_FIT PASS
SHORT PASS
OVERFLOW PASS
WRONG_PORT PASS
UNALIGNED_REJECT PASS
DMA gateway hybrid smoke PASS
```

## Dedicated FSBL trace diagnostic image

- Output:
  - `HCS_SOC\sd_boot\ax7020_dma_raw_copy_stream_smoke_fsbl_trace\BOOT.BIN`
- Current status:
  - dedicated FSBL trace diagnostic image
  - uses the same stream-smoke bitstream and stream-smoke app as the official dedicated image
  - changes only the dedicated stream-smoke FSBL behavior
- Diagnostic contract:
  - first trusted breadcrumb must be:
    - `FSBL_DIAG AFTER_PS7_INIT`
  - must not emit:
    - `FSBL_DIAG ENTER_MAIN`
  - each breadcrumb must use `xil_printf(...\r\n)` and a UART TXEMPTY drain
- Gate:
  - diagnostic only; not part of the normal board-test order
  - it is not a gateway-unblocking image

## Dedicated FSBL no-post-config diagnostic image

- Output:
  - `HCS_SOC\sd_boot\ax7020_dma_raw_copy_stream_smoke_fsbl_nopostcfg\BOOT.BIN`
- Current status:
  - dedicated FSBL no-post-config diagnostic image
  - uses the same stream-smoke bitstream and stream-smoke app as the official dedicated image
  - changes only the dedicated stream-smoke FSBL by skipping `ps7_post_config()` on the
    with-bit path
  - current board evidence:
    - reaches the app banner
    - does not complete `DMA stream smoke PASS`
- Gate:
  - diagnostic only; not part of the normal board-test order
  - if it reaches:
    - `DMA stream smoke PASS`
    then the remaining blocker is concentrated in the dedicated FSBL post-config / handoff window
  - gateway stays blocked until the official dedicated stream-smoke image also reaches that same pass log
  - do not use it to clear Phase 3 or unblock gateway until it matches the temporary baseline UART pass criteria

## Dedicated FSBL handofflite diagnostic image

- Output:
  - `HCS_SOC\sd_boot\ax7020_dma_raw_copy_stream_smoke_fsbl_handofflite\BOOT.BIN`
- Current status:
  - dedicated FSBL handofflite diagnostic image
  - uses the same stream-smoke bitstream and stream-smoke app as the official dedicated image
  - keeps only the handoff-window UART breadcrumbs inside `FsblHandoff()`
  - current board evidence:
    - `DMA stream smoke PASS`
- Diagnostic contract:
  - must emit only:
    - `FSBL_DIAG BEFORE_POST_CONFIG`
    - `FSBL_DIAG AFTER_POST_CONFIG`
    - `FSBL_DIAG BEFORE_HANDOFF`
  - must not emit:
    - `FSBL_DIAG AFTER_PS7_INIT`
    - `FSBL_DIAG BEFORE_PCAP_LOAD`
    - `FSBL_DIAG AFTER_PCAP_LOAD`
- Gate:
  - diagnostic only; not part of the normal board-test order
  - if it passes while `handoffdelay` fails, pure delay is not sufficient and UART / drain side effects remain part of the perturbation

## Dedicated FSBL handoffdelay diagnostic image

- Output:
  - `HCS_SOC\sd_boot\ax7020_dma_raw_copy_stream_smoke_fsbl_handoffdelay\BOOT.BIN`
- Current status:
  - dedicated FSBL handoffdelay diagnostic image
  - uses the same stream-smoke bitstream and stream-smoke app as the official dedicated image
  - emits no new FSBL UART breadcrumbs
  - adds only two fixed delay-spin perturbations in the with-bit handoff path:
    - after `ps7_post_config()`
    - before `FsblHookBeforeHandoff()`
  - current board evidence:
    - `DMA stream smoke PASS`
- Gate:
  - diagnostic only; not part of the normal board-test order
  - if it reaches `DMA stream smoke PASS`, the remaining blocker is primarily the with-bit `post_config -> handoff` timing window

## Deprecated historical images

Do not use these as board startup judges:

- `HCS_SOC\sd_boot\official_platform_smoke\image_a_nobit`
- `HCS_SOC\sd_boot\official_platform_smoke\image_b_withbit`
- `HCS_SOC\sd_boot\ax7020_dma_raw_copy_*_diag\BOOT.BIN`

Reason:

- They are mixed repackaged artifacts
- They do not prove the current repo's hardware handoff chain
- They have already failed on hardware while the vendor `ps_uart` baseline passed
- The staged raw-copy diag images remain useful for lab forensics, but they are no longer board-entry artifacts once the full smoke baseline passes
