# Delivery Repo Layout Design

**Date:** 2026-04-06

**Goal:** Reorganize the repository into a handoff-ready layout that is clean enough to share on GitHub without changing the active shadow-mirror build path.

## Scope

This pass is a delivery-layout cleanup, not a functional refactor.

The active shadow-mirror implementation, reports, and build/export/test entrypoints stay in place:

- `rtl/`
- `constraints/`
- `scripts/`
- `tests/`
- `tb/`
- `HCS_SOC/HCS_SOC.xpr`
- `HCS_SOC/HCS_SOC.srcs/`
- `HCS_SOC/HCS_SOC.runs/`
- `HCS_SOC/ax7020_udp_gateway_shadow_mirror_app/`
- `HCS_SOC/ax7020_udp_gateway_shadow_mirror_platform_xsct/`
- `HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror/`

## Layout Principles

1. Keep the current active release path stable.
2. Move logs, temporary workdirs, and one-off debug artifacts into archive roots.
3. Move historical non-active project families into explicit `legacy/` roots.
4. Keep current evidence and golden baseline documents under `doc/reports/`.
5. Make the repository readable to a new collaborator without requiring them to infer which folders are active.

## Target Structure

### Root

Primary roots:

- `rtl/`
- `constraints/`
- `scripts/`
- `tests/`
- `tb/`
- `doc/`
- `archive/`
- `HCS_SOC/`
- `legacy/`

Archive-only roots:

- `archive/root_runtime_logs/serial/`
- `archive/root_tool_logs/`
- `archive/root_debug_scripts/`
- `archive/root_backups/`
- `archive/root_temp_workdirs/`

Legacy-only roots:

- `legacy/root_projects/`
- `legacy/root_tools/`

### HCS_SOC

Primary active roots remain at the top level of `HCS_SOC/`.

Historical content is grouped under:

- `HCS_SOC/legacy/apps/`
- `HCS_SOC/legacy/platforms/`
- `HCS_SOC/legacy/sd_boot/`
- `HCS_SOC/legacy/artifacts/`

Archive content stays under:

- `HCS_SOC/archive/triage/`
- `HCS_SOC/archive/xsa_extracts/`
- `HCS_SOC/archive/temp_workdirs/`

## Move Rules

### Safe archive moves

- Root `board_*.txt` logs -> `archive/root_runtime_logs/serial/`
- Root temp extraction and scratch dirs -> `archive/root_temp_workdirs/`
- Root temporary scripts (`_tmp_*`, one-off `.tcl`, ad-hoc helpers) -> `archive/root_debug_scripts/`
- Root crash/log spillover -> `archive/root_tool_logs/`
- HCS_SOC scratch files (`_cbc_*`, `_tmp_*`, temp XSA unpack dirs) -> existing `HCS_SOC/archive/`

### Safe legacy grouping

Move historical, non-active root project families that are not part of the active shadow-mirror release path into `legacy/root_projects/`.

Move historical `HCS_SOC` app/platform/sd_boot families that are not:

- `ax7020_udp_gateway_shadow_mirror_app/`
- `ax7020_udp_gateway_shadow_mirror_platform_xsct/`
- `sd_boot/ax7020_udp_gateway_shadow_mirror/`

into `HCS_SOC/legacy/`.

## Non-Goals

- No RTL behavior changes
- No build system redesign
- No renaming of active shadow-mirror roots
- No attempt to make every historical script still runnable from its old path

## Acceptance Criteria

1. Root directory clearly separates active code, docs, archive, and legacy.
2. `HCS_SOC/` clearly separates active shadow-mirror content from historical families.
3. Existing repository layout tests still pass after updates.
4. The active shadow-mirror path is still obvious and unchanged.
