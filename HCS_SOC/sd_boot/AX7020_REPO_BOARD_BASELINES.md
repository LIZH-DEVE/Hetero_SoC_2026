# AX7020 Repo-Owned Board Images

This document defines the board-test order for repo-owned images.

## Board-test order

Always test in this order:

1. `ax7020_vendor_ps_uart_baseline`
2. `ax7020_repo_design1_uart_baseline`
3. `ax7020_dma_mvp_smoke_system`

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

## Deprecated historical images

Do not use these as board startup judges:

- `HCS_SOC\sd_boot\official_platform_smoke\image_a_nobit`
- `HCS_SOC\sd_boot\official_platform_smoke\image_b_withbit`

Reason:

- They are mixed repackaged artifacts
- They do not prove the current repo's hardware handoff chain
- They have already failed on hardware while the vendor `ps_uart` baseline passed
