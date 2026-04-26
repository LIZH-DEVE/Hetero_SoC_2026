# Hetero_SoC_2026

This repository contains the current delivery baseline for the `udp_gateway_shadow_mirror_wrapper` Phase C active path.

The repository has been reorganized for handoff and GitHub delivery. Start from this README, then use the linked layout and baseline documents before making any build or hardware assumptions.

## Current Baseline

The current defensible baseline is the version that has physical closure and board-level evidence for:

- AES hardware datapath
- SM4 hardware datapath
- ACL counted blocking behavior
- TXCAP-backed FastPath
- replay / lock / reauth security flow
- 18-scenario benchmark matrix

Golden baseline archive:

- [`doc/reports/golden_baseline/shadow_mirror_20260406_180500/BASELINE_MANIFEST.md`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/golden_baseline/shadow_mirror_20260406_180500/BASELINE_MANIFEST.md)

Frozen `BOOT.BIN` SHA256:

- `8D8501A0FD5A59B8511DA88507E20068DFC3D866E7E9CCD1A8AD47F50B2C8A72`

## Not Implemented In The Active FPGA Path

Do not treat these as implemented in the active FPGA datapath:

- true CBC
- zero-copy FastPath
- complete NIC datapath
- optimized DMA mainline
- 256-beat burst
- outstanding depth 4
- dual-core default enablement

`CBC Phase 1 readiness` exists, but it is metadata and state readiness only. It is not active CBC computation.

## Repository Entry Points

Read these first:

- [`doc/DELIVERY_LAYOUT.md`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/DELIVERY_LAYOUT.md)
- [`doc/REPO_STRUCTURE.md`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/REPO_STRUCTURE.md)
- [`doc/reports/golden_baseline/shadow_mirror_20260406_180500/BASELINE_MANIFEST.md`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/golden_baseline/shadow_mirror_20260406_180500/BASELINE_MANIFEST.md)

Active roots:

- [`rtl/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl)
- [`constraints/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/constraints)
- [`tests/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/tests)
- [`doc/reports/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports)
- [`HCS_SOC/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC)

Historical and temporary material has been moved under:

- [`legacy/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/legacy)
- [`archive/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/archive)
- [`HCS_SOC/legacy/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/legacy)
- [`HCS_SOC/archive/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/archive)

## Active Build And Release Path

The active release flow uses:

- [`HCS_SOC/HCS_SOC.xpr`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr)
- [`HCS_SOC/ax7020_udp_gateway_shadow_mirror_app/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/ax7020_udp_gateway_shadow_mirror_app)
- [`HCS_SOC/ax7020_udp_gateway_shadow_mirror_platform_xsct/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/ax7020_udp_gateway_shadow_mirror_platform_xsct)
- [`HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror)
- [`HCS_SOC/udp_gateway_shadow_mirror_wrapper.xsa`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/udp_gateway_shadow_mirror_wrapper.xsa)
- [`HCS_SOC/udp_gateway_shadow_mirror_wrapper.bit`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/udp_gateway_shadow_mirror_wrapper.bit)

## Environment Requirements

To rebuild and reproduce the hardware flow you need:

- Windows
- Xilinx Vivado 2024.1
- matching ARM / Vitis build environment
- AX7020 board
- either SD or JTAG board access

If you only need the source tree, reports, and evidence, board hardware is not required.

## Quick Start

### 1. Get the delivery branch

```powershell
git clone https://github.com/LIZH-DEVE/Hetero_SoC_2026.git
cd Hetero_SoC_2026
git checkout final-release
```

### 2. Read the delivery documents

```powershell
Get-Content .\doc\DELIVERY_LAYOUT.md
Get-Content .\doc\REPO_STRUCTURE.md
Get-Content .\doc\reports\golden_baseline\shadow_mirror_20260406_180500\BASELINE_MANIFEST.md
```

### 3. Rebuild the active app

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\HCS_SOC\build_ax7020_udp_gateway_shadow_mirror_app.ps1
```

### 4. Rebuild the active boot image

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\HCS_SOC\build_ax7020_udp_gateway_shadow_mirror_boot.ps1
```

### 5. Run repository validation

```powershell
py -3 -m unittest tests.test_repository_layout_contracts tests.test_udp_gateway_shadow_mirror_release tests.test_udp_gateway_shadow_runtime_contracts tests.test_dma_gateway_hybrid_contracts tests.test_shadow_mirror_cbc_readiness_contracts tests.test_day21_benchmark_matrix -v
```

### 6. Run board checks

SD path:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_board_check.ps1 -AssumeRunning
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_acl_check.ps1 -AssumeRunning
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_fastpath_board_check.ps1 -AssumeRunning
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_security_check.ps1 -AssumeRunning
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_performance_check.ps1 -AssumeRunning
```

JTAG path:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\shadow_mirror_jtag_run.ps1
```

## Physical Snapshot

Latest `impl_1` numbers:

- top-level Slice: `11081 / 13300 = 83.32%`
- top-level LUT as Memory: `267 / 17400 = 1.53%`
- top-level Block RAM Tile: `32.5 / 140 = 23.21%`
- `shadow_data_region` Slice: `10407 / 10944 = 95.65%`
- `shadow_data_region` Block RAM Tile: `32 / 36 = 88.89%`
- `WNS`: `4.561ns`
- `WHS`: `0.017ns`
- routed DRC: `0 violations`

Physical evidence:

- [`doc/reports/golden_baseline/shadow_mirror_20260406_180500/physical_reports/`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/golden_baseline/shadow_mirror_20260406_180500/physical_reports)

## Performance Snapshot

Latest stable board performance:

- AES: `2.774460x`
- SM4: `2.102386x`

Evidence:

- [`doc/reports/board_benchmarks/shadow_mirror_20260406_002824/board_bench_summary.md`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/board_benchmarks/shadow_mirror_20260406_002824/board_bench_summary.md)
- [`doc/reports/board_bench_matrix/shadow_mirror_20260406_110058/bench_matrix_summary.md`](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/board_bench_matrix/shadow_mirror_20260406_110058/bench_matrix_summary.md)

## Delivery Boundary

Use this language when handing the repository to others:

- This repository contains the active `shadow_mirror` baseline, validation evidence, and development records.
- The currently completed fast path is the block-crypto mainline plus ACL, security, and TXCAP-backed FastPath evidence.
- The repository does not claim true CBC, zero-copy FastPath, complete NIC datapath, or optimized DMA as active FPGA baseline features.
- `CBC Phase 1 readiness` only means metadata and state readiness. It does not mean CBC is enabled.

## GitHub

- Repository: [LIZH-DEVE/Hetero_SoC_2026](https://github.com/LIZH-DEVE/Hetero_SoC_2026)
- Recommended branch: `final-release`

