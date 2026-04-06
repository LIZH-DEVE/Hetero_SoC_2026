# Repository Structure

`doc/` is the primary human-facing documentation root for this repository. Put project status, reports, handoff summaries, and cleanup notes here.

`docs/` is reserved for tooling or workflow-specific documentation. It is not the primary project report tree.

## Active Code Roots

- `rtl/`
- `constraints/`
- `scripts/`
- `tests/`
- `tb/`
- `handoff/`
- `HCS_SOC/ax7020_udp_gateway_shadow_mirror_app/`
- `HCS_SOC/ax7020_udp_gateway_shadow_mirror_platform_xsct/`
- `HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror/`

## Archive Roots

- `archive/root_runtime_logs/serial/`
- `archive/root_tool_logs/`
- `archive/root_debug_scripts/`
- `archive/root_backups/`
- `archive/root_temp_workdirs/`
- `archive/root_temp_workdirs/local_workspace_state/`
- `doc/archive/root_notes/`
- `doc/archive/hcs_soc_notes/`
- `HCS_SOC/archive/triage/`
- `HCS_SOC/archive/xsa_extracts/`
- `HCS_SOC/archive/temp_workdirs/`

## Legacy Roots

- `legacy/root_projects/`
- `legacy/root_tools/`
- `HCS_SOC/legacy/apps/`
- `HCS_SOC/legacy/platforms/`
- `HCS_SOC/legacy/sd_boot/`
- `HCS_SOC/legacy/artifacts/`
- `HCS_SOC/legacy/scripts/`
- `HCS_SOC/legacy/workspaces/`

## HCS_SOC Layout

Keep the current shadow-mirror release path in the top level of `HCS_SOC/`. Move floorplan scratch files, XSA extract directories, and temporary exploration workdirs into `HCS_SOC/archive/`.

Historical functional families such as the older DMA raw-copy, GEM0, official probe, repo baseline, stream smoke, and network-inject trees are grouped under `legacy/` and `HCS_SOC/legacy/`. They remain part of the repository history, but they are not the active shadow-mirror release path.

Do not move the active Vivado project roots that are required by the current build:

- `HCS_SOC/HCS_SOC.xpr`
- `HCS_SOC/HCS_SOC.srcs/`
- `HCS_SOC/HCS_SOC.runs/`
- `HCS_SOC/HCS_SOC.gen/`
- `HCS_SOC/HCS_SOC.ip_user_files/`
- `HCS_SOC/HCS_SOC.cache/`

## Documentation Rules

- Keep current status and board evidence under `doc/reports/`.
- Move one-off root notes into `doc/archive/root_notes/`.
- Move HCS-specific legacy notes into `doc/archive/hcs_soc_notes/`.
- Keep delivery-facing layout guidance in `doc/DELIVERY_LAYOUT.md`.
- Move local IDE and workspace state such as `.claude/`, `.trae/`, `.wsdata/`, `.simlibs/`, and `.rigel_lopper/` into `archive/root_temp_workdirs/local_workspace_state/` instead of leaving them in the repository root.
