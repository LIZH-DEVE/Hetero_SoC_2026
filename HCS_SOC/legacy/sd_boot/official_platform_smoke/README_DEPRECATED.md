# Deprecated Mixed Smoke Images

These `official_platform_smoke` images are preserved only as historical artifacts.

They must not be used as authoritative board startup judges.

## Why they are deprecated

They were built from a mixed source chain:

- vendor `06_net_test` FSBL
- vendor `06_net_test` bitstream for the `withbit` variant
- repo-built UART smoke application ELF

That means they do not validate the current repo's own Vivado/XSA/FSBL handoff chain.

## What to use instead

Use this board-test order:

1. `..\ax7020_vendor_ps_uart_baseline\BOOT.BIN`
2. `..\ax7020_repo_design1_uart_baseline\BOOT.BIN`
3. `..\ax7020_dma_mvp_smoke_system\BOOT.BIN`

Important timing rule for step 3:

- `ax7020_dma_mvp_smoke_system` is not allowed on board unless the current `system_wrapper` routed timing is clean.
- Required gate:
  - `WNS >= 0`
  - `TNS = 0`
  - setup failing endpoints = `0`
  - hold failing endpoints = `0`
- Enforced by:
  - `HCS_SOC\invoke_vivado_timing_triage.ps1`
  - `HCS_SOC\read_vivado_timing_summary.ps1`
  - `HCS_SOC\build_ax7020_dma_mvp_smoke_fresh.ps1`
  - `HCS_SOC\deploy_ax7020_dma_mvp_smoke_to_sd.ps1`
