# Phase C Board Benchmark Summary

Board-first acceptance source: AX7020 board UDP BENCH control responses.

- Target IP: `192.168.1.20`
- Source IP: `192.168.1.11`
- Control port: `4662`
- Repeats per length: `8`

PS software baseline: same-board software path measured by `gateway_sw_encrypt_buffer()`.
Hardware speedup vs PS software: same-board hardware path measured by `gateway_hw_encrypt_buffer_sync()`.
Target speedup gate: average speedup per algorithm must be `>= 1.000000x`.
Short payload note: `16B` and `32B` rows may remain `<1.0x`; failure should be judged on average result, not isolated short-packet rows.
Target result: `FAIL`

## AES

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 8 | 41 | 57 | 5.125000 | 7.125000 | 2.977325 | 2.141584 | 0.719298 |
| 32 | 8 | 73 | 76 | 9.125000 | 9.500000 | 3.344392 | 3.212377 | 0.960526 |
| 128 | 8 | 273 | 266 | 34.125000 | 33.250000 | 3.577152 | 3.671288 | 1.026316 |
| 512 | 8 | 1074 | 1026 | 134.250000 | 128.250000 | 3.637104 | 3.807261 | 1.046784 |
| 1472 | 8 | 3078 | 2927 | 384.750000 | 365.875000 | 3.648625 | 3.836853 | 1.051589 |

Summary: min speedup `0.719298x`, max speedup `1.051589x`, avg speedup `0.960903x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 8 | 19 | 51 | 2.375000 | 6.375000 | 6.424753 | 2.393536 | 0.372549 |
| 32 | 8 | 28 | 76 | 3.500000 | 9.500000 | 8.719308 | 3.212377 | 0.368421 |
| 128 | 8 | 83 | 266 | 10.375000 | 33.250000 | 11.765813 | 3.671288 | 0.312030 |
| 512 | 8 | 306 | 1026 | 38.250000 | 128.250000 | 12.765523 | 3.807261 | 0.298246 |
| 1472 | 8 | 864 | 2927 | 108.000000 | 365.875000 | 12.998228 | 3.836853 | 0.295183 |

Summary: min speedup `0.295183x`, max speedup `0.372549x`, avg speedup `0.329286x`.
