# RAWCOPY UART Diag Runtime Bisect

This document fixes the staged runtime bisect order for the raw-copy bring-up lane.

Do not skip levels.

## Fixed 13-Layer Order

### 1. Vendor UART Baseline
Image:
- `ax7020_vendor_ps_uart_baseline`

Pass:
- UART repeatedly prints `Hello ALINX!`

Fail:
- `Bytes=0`
- no repeated `Hello ALINX!`

Meaning:
- If this fails, stop. Do not continue to any raw-copy image.

### 2. Repo design1 UART Baseline
Image:
- `ax7020_repo_design1_uart_baseline`

Pass:
- UART prints `REPO DESIGN1 UART BASELINE`
- UART prints `UART1 OK`
- UART prints `REPO_HEARTBEAT ...`

Fail:
- `Bytes=0`
- no repo heartbeat

Meaning:
- If this fails, stop. The repo-owned PS/FSBL/UART chain is not healthy.

### 3. Raw-copy UART-Only Diagnostic
Image:
- `ax7020_dma_raw_copy_uart_diag`

Purpose:
- Prove the dedicated raw-copy platform can boot and talk over UART before any DMA runtime is involved.

Pass:
- UART prints `RAWCOPY UART DIAG`
- UART prints `RAWCOPY_PLATFORM_OK`
- UART prints `RAWCOPY_UART_HEARTBEAT ...`

Fail:
- `Bytes=0`
- no `RAWCOPY_PLATFORM_OK`

Meaning:
- If this fails, stop. The dedicated raw-copy platform handoff is still broken before DMA.

### 4. Raw-copy Includes Diagnostic
Image:
- `ax7020_dma_raw_copy_includes_diag`

Purpose:
- Prove that simply including raw-copy headers/types does not break early startup on the dedicated raw-copy platform.

Pass:
- UART prints `RAWCOPY INCLUDES DIAG`
- UART prints `RAWCOPY_INCLUDE_HEADERS_OK`
- UART prints `RAWCOPY_INCLUDE_HEARTBEAT ...`

Fail:
- `Bytes=0`
- no includes heartbeat

Meaning:
- If level 3 passes and this fails, the fault appears as soon as raw-copy headers/types enter the image.

### 5. Raw-copy Static Regions Diagnostic
Image:
- `ax7020_dma_raw_copy_static_regions_diag`

Purpose:
- Prove that merely adding the raw-copy `.dma_*` sections and static regions does not break early startup.

Pass:
- UART prints `RAWCOPY STATIC REGIONS DIAG`
- UART prints `RAWCOPY_STATIC_REGIONS_OK`
- UART prints `RAWCOPY_STATIC_HEARTBEAT ...`

Fail:
- `Bytes=0`
- no static-regions heartbeat

Meaning:
- If level 4 passes and this fails, the fault appears when the custom `.dma_*` sections and static region objects enter the image.

### 6. Raw-copy Memory Prep Diagnostic
Image:
- `ax7020_dma_raw_copy_memory_prep_diag`

Purpose:
- Add `clear_regions()` and source/destination buffer seeding, but still avoid DMA MMIO and DMA API calls.

Pass:
- UART prints stage banner for memory-prep diagnostic
- UART prints a success marker after region clear/seed
- UART continues heartbeat output

Fail:
- `Bytes=0`
- no stage marker

Meaning:
- If level 5 passes and this fails, the first bad delta is memory-touching prep logic, not DMA MMIO.

### 7. Raw-copy Driver-Init Diagnostic
Image:
- `ax7020_dma_raw_copy_driver_init_diag`

Purpose:
- Add the first real DMA MMIO touch: `dma_ring_init()`, but still stop short of `soft_reset`, submit, doorbell, poll, or compare.

Pass:
- UART prints `RAWCOPY DRIVER INIT DIAG`
- UART prints `RAWCOPY_DRIVER_INIT_OK`
- UART prints `RAWCOPY_DRIVER_HEARTBEAT ...`

Fail:
- `Bytes=0`
- no driver-init marker

Meaning:
- If level 6 passes and this fails, the first bad delta is the first CSR/MMIO writes in `dma_ring_init()`, not the later `soft_reset`/submit flow.

### 8. Raw-copy Soft-Reset Diagnostic
Image:
- `ax7020_dma_raw_copy_soft_reset_diag`

Purpose:
- Add exactly one `dma_ring_soft_reset()` call after the already-proven `dma_ring_init()` path, but still stop before reinit, submit, doorbell, poll, invalidate, or compare.

Pass:
- UART prints `RAWCOPY SOFT RESET DIAG`
- UART prints `RAWCOPY_SOFT_RESET_STAGE BEFORE_SOFT_RESET`
- UART prints `RAWCOPY_SOFT_RESET_STAGE AFTER_SOFT_RESET`
- UART prints `RAWCOPY_SOFT_RESET_OK`
- UART prints `RAWCOPY_SOFT_RESET_HEARTBEAT ...`

Fail:
- `Bytes=0`
- no soft-reset marker
- silence after `BEFORE_SOFT_RESET`

Meaning:
- If level 7 passes and this fails, the first bad delta is the `CTRL` write pair inside `dma_ring_soft_reset()`, not submit or poll.

### 9. Raw-copy Reinit-After-Reset Diagnostic
Image:
- `ax7020_dma_raw_copy_reinit_after_reset_diag`

Purpose:
- Prove that the ring can be initialized again after `dma_ring_soft_reset()`, but still stop before any submit, doorbell, poll, invalidate, or compare logic.

Pass:
- UART prints `RAWCOPY REINIT AFTER RESET DIAG`
- UART prints `RAWCOPY_REINIT_AFTER_RESET_STAGE BEFORE_REINIT`
- UART prints `RAWCOPY_REINIT_AFTER_RESET_STAGE AFTER_REINIT`
- UART prints `RAWCOPY_REINIT_AFTER_RESET_OK`
- UART prints `RAWCOPY_REINIT_HEARTBEAT ...`

Fail:
- `Bytes=0`
- no reinit marker
- silence after `BEFORE_REINIT`

Meaning:
- If level 8 passes and this fails, the first bad delta is the reset-after-reinit path, not submit or poll.

### 10. Raw-copy Submit Diagnostic
Image:
- `ax7020_dma_raw_copy_submit_diag`

Purpose:
- Add exactly one `dma_ring_submit_raw_copy()` call after the proven reinit path, but still stop before `wait_csw`, invalidate, compare, or full smoke.

Pass:
- UART prints `RAWCOPY SUBMIT DIAG`
- UART prints `RAWCOPY_SUBMIT_STAGE REINIT_DONE`
- UART prints `RAWCOPY_SUBMIT_STAGE BEFORE_SUBMIT`
- UART prints `RAWCOPY_SUBMIT_STAGE AFTER_SUBMIT rc=... sw_tail=...`
- UART prints `RAWCOPY_SUBMIT_OK`
- UART prints `RAWCOPY_SUBMIT_HEARTBEAT ...`

Fail:
- `Bytes=0`
- no submit marker
- silence after `BEFORE_SUBMIT`
- `AFTER_SUBMIT rc!=0`

Meaning:
- `dma_ring_submit_raw_copy()` is treated as a single layer.
- It already includes descriptor writes, cache flush, `RING_SW_TAIL`, and `DOORBELL`.
- If level 9 passes and this fails, the first bad delta is inside submit/doorbell, not poll or compare.

### 11. Raw-copy Wait-CSW Diagnostic
Image:
- `ax7020_dma_raw_copy_wait_csw_diag`

Purpose:
- Add exactly one `wait_for_csw(...)` step after a successful submit, but still stop before invalidate/compare.

Pass:
- UART prints `RAWCOPY WAIT CSW DIAG`
- UART prints `RAWCOPY_WAIT_CSW_STAGE SUBMIT_DONE`
- UART prints `RAWCOPY_WAIT_CSW_STAGE BEFORE_WAIT`
- UART prints `RAWCOPY_WAIT_CSW_STAGE AFTER_WAIT rc=... csw=0x...`
- UART prints `RAWCOPY_WAIT_CSW_OK`
- UART prints `RAWCOPY_WAIT_CSW_HEARTBEAT ...`

Fail:
- `Bytes=0`
- no wait marker
- silence after `BEFORE_WAIT`
- `AFTER_WAIT rc!=0`

Meaning:
- If level 10 passes and this fails, the first bad delta is the poll/completion path, not invalidate or compare.
- Important implementation note:
  the current fetcher treats `head_ptr == sw_tail_ptr` as empty.
  A `ring_size` of `1` collapses back to `head=tail=0` immediately after submit.
  Therefore, completion-path levels from here onward must use a `2-entry` ring.

### 12. Raw-copy Invalidate-Compare Diagnostic
Image:
- `ax7020_dma_raw_copy_invalidate_compare_diag`

Purpose:
- Add destination invalidate and payload compare after a successful wait-for-CSW path, but stop short of the final full smoke formatting.

Pass:
- UART prints invalidate/compare stage markers
- UART prints a compare success marker
- UART continues heartbeat output

Fail:
- `Bytes=0`
- no compare success marker
- compare mismatch banner

Meaning:
- If level 11 passes and this fails, the first bad delta is cache invalidate or payload compare handling.

### 13. Dedicated raw-copy smoke with-bit
Image:
- `ax7020_dma_raw_copy_smoke`

Purpose:
- Full dedicated raw-copy image including bitstream and app.

Pass:
- UART prints `DMA raw-copy smoke image`
- UART prints `RAWCOPY_STAGE INIT`
- UART prints `RAWCOPY_STAGE RESET`
- UART prints `RAWCOPY_STAGE SUBMIT`
- UART prints `RAWCOPY_STAGE WAIT_CSW`
- UART prints `CSW=0x...`
- UART prints `RAWCOPY_STAGE INVALIDATE_DST`
- UART prints `RAWCOPY_STAGE COMPARE`
- UART prints `DMA raw-copy smoke PASS`

Fail:
- `Bytes=0`
- any `DMA raw-copy smoke FAIL`
- missing `CSW=0x...`
- missing final `PASS`

Meaning:
- This is the only level that proves the full raw-copy board image is working.

## Decision Rules

### Evidence levels

There are two valid evidence levels for board logs:

1. Complete evidence
- Banner + stage markers + heartbeat are present in the captured window.

2. Control-flow evidence
- The stage-specific heartbeat is present.
- This is enough to mark the level as passed when source control flow guarantees that the heartbeat loop is reached only after the stage's key call returns.

Use control-flow evidence when the capture script starts too late and misses the earliest banner lines.

If you want complete evidence, use this capture order:
1. Start the UART capture script first.
2. While the script is listening, power the board off for 3 seconds.
3. Power the board back on.

- A higher level is invalid if any lower level has not passed.
- `Bytes=0` is always a hard fail for that level.
- A level passes with either complete evidence or control-flow evidence.
- Do not reinterpret a later-layer failure as a board failure if lower UART baselines already passed.
- Level 3 is the platform-only gate.
- Level 5 isolates custom section/static-region effects.
- Level 8 isolates the soft-reset path.
- Level 9 isolates reinit-after-reset.
- Level 10 isolates submit/doorbell.
- Level 11 isolates wait-for-CSW.
- Level 12 isolates invalidate/compare.
- Level 13 is the full-image gate.
