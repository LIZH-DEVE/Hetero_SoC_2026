# Shadow Mirror SD Boot Regression Recovery

Date:
- `2026-04-05`

Scope:
- isolate the `SD cold boot` regression introduced after the `2026-04-04` stable board-proven image
- recover a release image that is reproducible from the current build scripts
- re-run the core `SD` board suite on the recovered image

## Final Acceptance Image

- Image: `HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror/BOOT.BIN`
- SHA256: `8D8501A0FD5A59B8511DA88507E20068DFC3D866E7E9CCD1A8AD47F50B2C8A72`

## Regression Symptom

The failing family reproduced the same hard symptom on real `SD` cold boot:
- `ping 192.168.1.20`: FAIL
- `hello`: TIMEOUT
- `board_check`: blocked at `HELLO`
- `UART`: no usable boot/runtime evidence

The same application family still ran under `JTAG`, so the regression was narrowed to the `SD` boot path rather than an immediate application crash.

## Isolation Strategy

The investigation used fixed `BOOT.BIN` variants so that `bit` and `app` could be tested independently.

Key result:
- `app_52B + current bit`: PASS on real `SD` cold boot
- therefore `current bit` was not the primary regression source

The final narrowing step reverted only the lwIP BSP hot-path file:
- `HCS_SOC/vitis_2023_udp_gateway_ws_2/ax7020_udp_gateway_platform/.../xemacpsif.c`

That revert changed the rebuilt application family and produced a new release image:
- `8D8501A0FD5A59B8511DA88507E20068DFC3D866E7E9CCD1A8AD47F50B2C8A72`

Current evidence therefore isolates the `SD` regression to the lwIP BSP `xemacpsif.c` path.

## Build Reproducibility

The important closeout result is not only that a custom test `BOOT.BIN` passed, but that the normal release path now reproduces the same passing image:

- `build_ax7020_udp_gateway_shadow_mirror_app.ps1`: PASS
- `build_ax7020_udp_gateway_shadow_mirror_boot.ps1`: PASS
- release `BOOT.BIN` SHA matches the board-proven test image exactly:
  - `8D8501A0FD5A59B8511DA88507E20068DFC3D866E7E9CCD1A8AD47F50B2C8A72`

## SD Board Validation

Validated on real `SD` cold boot:
- `ping`: PASS
- `hello`: PASS
- `board_check`: PASS
- `ACL`: PASS
- `FastPath`: PASS
- `Security`: PASS
- `Performance`: PASS

Board performance capture:
- directory: `doc/reports/board_benchmarks/shadow_mirror_20260405_204158`
- AES avg speedup = `2.773757x`
- SM4 avg speedup = `2.102749x`

Representative runtime evidence:
- `LIVE_CTRL PASS`
- `LIVE_AES PASS`
- `LIVE_SM4 PASS`
- `SHADOW_AES PASS`
- `SHADOW_SM4 PASS`
- `SHADOW_ACL_DROP PASS`
- `FASTPATH_HIT_COUNT` increased with `FASTPATH_FALLBACK_COUNT = 0`
- replay / lock / timeout / re-auth checks all passed

## Final Judgment

- the `SD` cold-boot regression is recovered
- the current release build is reproducible
- the recovered release image is board-proven on `SD`
- the current accepted release baseline is:
  - `BOOT.BIN SHA256 = 8D8501A0FD5A59B8511DA88507E20068DFC3D866E7E9CCD1A8AD47F50B2C8A72`
