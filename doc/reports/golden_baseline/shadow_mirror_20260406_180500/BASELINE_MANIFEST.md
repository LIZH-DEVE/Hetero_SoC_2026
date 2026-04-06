# Shadow Mirror Golden Baseline Manifest

Archive root:

- [shadow_mirror_20260406_180500](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/golden_baseline/shadow_mirror_20260406_180500)

## Purpose

This archive freezes the current `udp_gateway_shadow_mirror_wrapper` release baseline before any zero-copy `FastPath` exploration.

This baseline is the version that currently supports:

- active `AES` datapath
- active `SM4` datapath
- ACL countered blocking behavior
- `TXCAP-backed FastPath`
- replay / lock / reauth security flow
- `18`-scenario benchmark matrix

## Core Hardware Artifacts

| Artifact | SHA256 |
|---|---|
| [udp_gateway_shadow_mirror_wrapper.bit](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/golden_baseline/shadow_mirror_20260406_180500/hardware/udp_gateway_shadow_mirror_wrapper.bit) | `75A9BEB522A6CBD9AAD2BC5EC41A778075D035F1CCBE8C5CDACAA49083EEDB41` |
| [udp_gateway_shadow_mirror_wrapper.xsa](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/golden_baseline/shadow_mirror_20260406_180500/hardware/udp_gateway_shadow_mirror_wrapper.xsa) | `EEBA633ACA641E96EBC4CCBFD97372918DEB282F6109E548E6453F30FFDDDADF` |
| [BOOT.BIN](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/golden_baseline/shadow_mirror_20260406_180500/hardware/BOOT.BIN) | `8D8501A0FD5A59B8511DA88507E20068DFC3D866E7E9CCD1A8AD47F50B2C8A72` |

## Physical Reports

| Artifact | SHA256 |
|---|---|
| [udp_gateway_shadow_mirror_wrapper_utilization_placed.rpt](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/golden_baseline/shadow_mirror_20260406_180500/physical_reports/udp_gateway_shadow_mirror_wrapper_utilization_placed.rpt) | `4A9B1AA4CD2678B2B273CE558EDF339B0670116A943B1C7FDFF02066D53F0BD9` |
| [udp_gateway_shadow_mirror_wrapper_timing_summary_routed.rpt](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/golden_baseline/shadow_mirror_20260406_180500/physical_reports/udp_gateway_shadow_mirror_wrapper_timing_summary_routed.rpt) | `0AB41C1933A993AAAA11FB39ED887FAACB2838D04ADF6BA0592258EC2B5652FC` |
| [udp_gateway_shadow_mirror_wrapper_drc_routed.rpt](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/golden_baseline/shadow_mirror_20260406_180500/physical_reports/udp_gateway_shadow_mirror_wrapper_drc_routed.rpt) | `48C8B3BCF8E7FD247A0A313BC23CD9DF7CA3D4615D2CA04C21616C55CDC42F04` |
| [_cbc_readiness_shadow_data_util.rpt](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/golden_baseline/shadow_mirror_20260406_180500/physical_reports/_cbc_readiness_shadow_data_util.rpt) | copied baseline reference |

## Validation Reports

| Artifact | SHA256 |
|---|---|
| [board_bench_summary.md](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/golden_baseline/shadow_mirror_20260406_180500/validation_reports/board_bench_summary.md) | `C6CB717A32EE7B25E5967DA84EC49076051CCF3B089958BFF26C589E2A2EAC1C` |
| [bench_matrix_summary.md](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/golden_baseline/shadow_mirror_20260406_180500/validation_reports/bench_matrix_summary.md) | `2A7E0EA84C7A1B2EC7C937159D5D1CAAA0BED98EB2519FCF60061D60FF00CDB3` |
| [2026-04-06_shadow_mirror_matrix_and_trimix_validation.md](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/golden_baseline/shadow_mirror_20260406_180500/validation_reports/2026-04-06_shadow_mirror_matrix_and_trimix_validation.md) | `CA8BFD2B2A0BBAAC6397DCCCC43CFCF7F845F69910979D0E54D794794AF409DC` |
| [2026-04-06_shadow_mirror_defense_assets.md](/D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/golden_baseline/shadow_mirror_20260406_180500/validation_reports/2026-04-06_shadow_mirror_defense_assets.md) | `E406A6915CC8E8059672556DD98D78000696A3D5A85381C9DF931984D315BC8E` |

## Frozen Capability Statement

### Defensible in this baseline

- `AES/SM4` active datapath
- ACL counted blocking behavior
- `TXCAP-backed FastPath`
- security replay / lock / reauth flow
- `18`-scenario matrix benchmark

### Not defensible in this baseline

- "ACL-hit always implies no reply"
- "FastPath-hit + AES-1472 + ACL-hit tri-mix is fully clean"
- zero-copy `FastPath`
- true `CBC`
- complete `NIC` datapath

## Physical Snapshot

- Top-level `Slice`: `11081 / 13300 = 83.32%`
- Top-level `LUT as Memory`: `267 / 17400 = 1.53%`
- Top-level `Block RAM Tile`: `32.5 / 140 = 23.21%`
- `shadow_data_region Slice`: `10407 / 10944 = 95.65%`
- `shadow_data_region Block RAM Tile`: `32 / 36 = 88.89%`
- Main-clock `WNS`: `4.561ns`
- Main-clock `WHS`: `0.017ns`
- Routed DRC: `0 violations`

## Archive Rule

This baseline should be treated as immutable.

If zero-copy `FastPath` work starts, compare against this archive rather than against moving workspace files.
