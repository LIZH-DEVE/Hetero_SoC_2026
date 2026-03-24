# AX7020 Vendor Board Baselines

These baseline images are copied verbatim from the vendor course package under:

- `D:\FPGAhanjia\Hetero_SoC_2026_3\AX7020_2023.1\course_s2_vitis`

They are the authoritative board bring-up baselines for this repository.

## Included images

### `ax7020_vendor_ps_hello_baseline`

- Source:
  - `01_ps_hello\Bootimage\BOOT.BIN`
- Target in repo:
  - `HCS_SOC\sd_boot\ax7020_vendor_ps_hello_baseline\BOOT.BIN`
- SHA256:
  - `AD7EDA549A64AD1DF936F44BF83DBA438A020A5BBFE2EF8AAD044CBEFD5E9328`
- Notes:
  - Minimal vendor PS hello image.
  - Useful as a vendor-origin cross-check, but not ideal for UART capture because it may only print once near boot.

### `ax7020_vendor_ps_uart_baseline`

- Source:
  - `08_ps_uart\Bootimage\BOOT.BIN`
- Target in repo:
  - `HCS_SOC\sd_boot\ax7020_vendor_ps_uart_baseline\BOOT.BIN`
- SHA256:
  - `A7F6DDF0750C6534A97097EB07753B121447477856383587A7F1005CE0231622`
- Notes:
  - Vendor UART baseline that continuously prints `Hello ALINX!`
  - This is the preferred board startup judge because it emits serial output every second.

## Board-level usage

Preferred deployment command:

```powershell
powershell -ExecutionPolicy Bypass -File D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\deploy_ax7020_vendor_ps_uart_baseline_to_sd.ps1 -SdDrive E:
```

Expected capture result on a healthy board:

```text
Hello ALINX!
Hello ALINX!
Hello ALINX!
```

## Important debugging rule

Do not use `official_platform_smoke/image_a_nobit` or `official_platform_smoke/image_b_withbit` as authoritative board startup judges.

Those images are mixed repo-generated smoke packages built from:

- `06_net_test` FSBL
- `06_net_test` bitstream for the `withbit` variant
- repo-built `ax7020_official_uart_smoke_app.elf`

They are useful as repo artifacts, but they are not the same as the vendor course release images and have already been shown to be unreliable as startup baselines on hardware.
