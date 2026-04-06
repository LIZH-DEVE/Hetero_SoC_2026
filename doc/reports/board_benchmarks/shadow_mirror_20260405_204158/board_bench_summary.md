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
| 16 | 1000 | 4914 | 3192 | 4.914000 | 3.192000 | 3.105167 | 4.780322 | 1.539474 |
| 32 | 1000 | 9059 | 4300 | 9.059000 | 4.300000 | 3.368758 | 7.097111 | 2.106744 |
| 128 | 1000 | 33916 | 11050 | 33.916000 | 11.050000 | 3.599195 | 11.047087 | 3.069321 |
| 512 | 1000 | 133390 | 37923 | 133.390000 | 37.923000 | 3.660554 | 12.875597 | 3.517391 |
| 1472 | 1000 | 382201 | 105120 | 382.201000 | 105.120000 | 3.672959 | 13.354344 | 3.635854 |

Summary: min speedup `1.539474x`, max speedup `3.635854x`, avg speedup `2.773757x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 2638 | 2455 | 2.638000 | 2.455000 | 5.784226 | 6.215393 | 1.074542 |
| 32 | 1000 | 3933 | 2855 | 3.933000 | 2.855000 | 7.759364 | 10.689169 | 1.377583 |
| 128 | 1000 | 11574 | 5280 | 11.574000 | 5.280000 | 10.546943 | 23.119377 | 2.192045 |
| 512 | 1000 | 42139 | 14891 | 42.139000 | 14.891000 | 11.587395 | 32.790360 | 2.829830 |
| 1472 | 1000 | 118547 | 38999 | 118.547000 | 38.999000 | 11.841789 | 35.996015 | 3.039745 |

Summary: min speedup `1.074542x`, max speedup `3.039745x`, avg speedup `2.102749x`.
