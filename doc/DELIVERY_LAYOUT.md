# Delivery Layout

This repository is organized for handoff and GitHub upload around one rule: keep the current shadow-mirror release path obvious, and push everything historical or temporary into explicit `archive/` and `legacy/` roots.

## Use These Roots For Current Work

- [`rtl/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl): active RTL
- [`constraints/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/constraints): active physical constraints
- [`scripts/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/scripts): active Python support scripts
- [`tests/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tests): active repository tests
- [`doc/reports/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports): current reports, evidence, golden baseline

## Current Shadow-Mirror Release Path

Use these directories and files for the active release flow:

- [`HCS_SOC/HCS_SOC.xpr`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr)
- [`HCS_SOC/ax7020_udp_gateway_shadow_mirror_app/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/ax7020_udp_gateway_shadow_mirror_app)
- [`HCS_SOC/ax7020_udp_gateway_shadow_mirror_platform_xsct/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/ax7020_udp_gateway_shadow_mirror_platform_xsct)
- [`HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror)
- [`HCS_SOC/udp_gateway_shadow_mirror_wrapper.xsa`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/udp_gateway_shadow_mirror_wrapper.xsa)
- [`HCS_SOC/udp_gateway_shadow_mirror_wrapper.bit`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/udp_gateway_shadow_mirror_wrapper.bit)

The active operational scripts intentionally remain at the top level of [`HCS_SOC/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC) so the current build, export, JTAG, board-check, security, and performance flow stays readable.

## Archive Roots

Use archive roots for one-off logs, temporary workdirs, and scratch files:

- [`archive/root_runtime_logs/serial/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/archive/root_runtime_logs/serial)
- [`archive/root_tool_logs/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/archive/root_tool_logs)
- [`archive/root_debug_scripts/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/archive/root_debug_scripts)
- [`archive/root_temp_workdirs/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/archive/root_temp_workdirs)
- [`archive/root_temp_workdirs/local_workspace_state/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/archive/root_temp_workdirs/local_workspace_state)
- [`HCS_SOC/archive/triage/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/archive/triage)
- [`HCS_SOC/archive/xsa_extracts/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/archive/xsa_extracts)
- [`HCS_SOC/archive/temp_workdirs/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/archive/temp_workdirs)

## Legacy Roots

Historical experiments and non-active release families now live in:

- [`legacy/root_projects/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/legacy/root_projects)
- [`legacy/root_tools/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/legacy/root_tools)
- [`HCS_SOC/legacy/apps/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/legacy/apps)
- [`HCS_SOC/legacy/platforms/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/legacy/platforms)
- [`HCS_SOC/legacy/sd_boot/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/legacy/sd_boot)
- [`HCS_SOC/legacy/artifacts/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/legacy/artifacts)
- [`HCS_SOC/legacy/scripts/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/legacy/scripts)
- [`HCS_SOC/legacy/workspaces/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/legacy/workspaces)

These paths are preserved for reference, but they are not the active shadow-mirror delivery path.

## Delivery Hygiene

Keep root-local IDE state and temporary workspace metadata out of the visible delivery surface. If these files are needed for local recovery, keep them under [`archive/root_temp_workdirs/local_workspace_state/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/archive/root_temp_workdirs/local_workspace_state) rather than at the repository top level.
