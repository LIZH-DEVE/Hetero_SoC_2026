# Phase C Board Benchmark Summary

Board-first acceptance source: AX7020 board UDP BENCH control responses.

- Target IP: `192.168.1.20`
- Source IP: `192.168.1.11`
- Control port: `4662`
- Repeats per length: `1000`

PS software baseline: same-board software path measured by `gateway_sw_encrypt_buffer()`.
Hardware speedup vs PS software: same-board hardware path measured by `gateway_hw_encrypt_buffer_sync()`.
Target speedup gate: average speedup per algorithm must be `>= 1.000000x`.
Short payload note: `16B` and `32B` rows may remain `<1.0x`; failure should be judged on average result, not isolated short-packet rows.
Target result: `PASS`

## AES

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 4914 | 3193 | 4.914000 | 3.193000 | 3.105167 | 4.778825 | 1.538992 |
| 32 | 1000 | 9323 | 4293 | 9.323000 | 4.293000 | 3.273365 | 7.108683 | 2.171675 |
| 128 | 1000 | 33916 | 11050 | 33.916000 | 11.050000 | 3.599195 | 11.047087 | 3.069321 |
| 512 | 1000 | 133349 | 37923 | 133.349000 | 37.923000 | 3.661679 | 12.875597 | 3.516309 |
| 1472 | 1000 | 381932 | 105120 | 381.932000 | 105.120000 | 3.675546 | 13.354344 | 3.633295 |

Summary: min speedup `1.538992x`, max speedup `3.633295x`, avg speedup `2.785918x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 2638 | 2455 | 2.638000 | 2.455000 | 5.784226 | 6.215393 | 1.074542 |
| 32 | 1000 | 3933 | 2861 | 3.933000 | 2.861000 | 7.759364 | 10.666752 | 1.374694 |
| 128 | 1000 | 11574 | 5280 | 11.574000 | 5.280000 | 10.546943 | 23.119377 | 2.192045 |
| 512 | 1000 | 42139 | 14891 | 42.139000 | 14.891000 | 11.587395 | 32.790360 | 2.829830 |
| 1472 | 1000 | 118550 | 39000 | 118.550000 | 39.000000 | 11.841490 | 35.995092 | 3.039744 |

Summary: min speedup `1.074542x`, max speedup `3.039744x`, avg speedup `2.102171x`.
