# Phase C Board Benchmark Summary

Board-first acceptance source: AX7020 board Stage 2 SG proof UART log.

- Target IP: `uart-proof`
- Source IP: `uart-proof`
- Control port: `0`
- Repeats per length: `1000`

PS software baseline: same-board software path measured by `gateway_sw_encrypt_buffer()`.
Hardware speedup vs PS software: same-board descriptor-driven DMA/crypto path measured by the Stage 2 proof image.
Target speedup gate: average speedup per algorithm must be `>= 1.000000x`.
Short payload note: `16B` and `32B` rows may remain `<1.0x`; failure should be judged on average result, not isolated short-packet rows.
Target result: `PASS`

## AES

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 5256 | 3344 | 5.256000 | 3.344000 | 2.903118 | 4.563035 | 1.571770 |
| 32 | 1000 | 9742 | 3469 | 9.742000 | 3.469000 | 3.132578 | 8.797226 | 2.808302 |
| 128 | 1000 | 36549 | 6885 | 36.549000 | 6.885000 | 3.339908 | 17.729893 | 5.308497 |
| 512 | 1000 | 143527 | 20320 | 143.527000 | 20.320000 | 3.402017 | 24.029589 | 7.063337 |
| 1472 | 1000 | 411651 | 53923 | 411.651000 | 53.923000 | 3.410191 | 26.033577 | 7.634052 |

Diagnostics:
- Hardware execution mode: `single-launch SG batch`
- Descriptor count: `1000`
- Doorbell count: `1`
- Last descriptor poll count: `199344`
- Actual length mismatch count: `0`

Summary: min speedup `1.571770x`, max speedup `7.634052x`, avg speedup `4.877192x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 2216 | 2604 | 2.216000 | 2.604000 | 6.885735 | 5.859750 | 0.850998 |
| 32 | 1000 | 3390 | 2755 | 3.390000 | 2.755000 | 9.002235 | 11.077161 | 1.230490 |
| 128 | 1000 | 10417 | 4000 | 10.417000 | 4.000000 | 11.718375 | 30.517578 | 2.604250 |
| 512 | 1000 | 38312 | 8801 | 38.312000 | 8.801000 | 12.744865 | 55.480201 | 4.353142 |
| 1472 | 1000 | 108155 | 20800 | 108.155000 | 20.800000 | 12.979600 | 67.490798 | 5.199760 |

Diagnostics:
- Hardware execution mode: `single-launch SG batch`
- Descriptor count: `1000`
- Doorbell count: `1`
- Last descriptor poll count: `76070`
- Actual length mismatch count: `0`

Summary: min speedup `0.850998x`, max speedup `5.199760x`, avg speedup `2.847728x`.
