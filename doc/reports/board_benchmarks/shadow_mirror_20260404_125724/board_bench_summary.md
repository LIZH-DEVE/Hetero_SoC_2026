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
| 16 | 1000 | 4913 | 3187 | 4.913000 | 3.187000 | 3.105799 | 4.787822 | 1.541575 |
| 32 | 1000 | 9060 | 4294 | 9.060000 | 4.294000 | 3.368386 | 7.107028 | 2.109921 |
| 128 | 1000 | 33916 | 11050 | 33.916000 | 11.050000 | 3.599195 | 11.047087 | 3.069321 |
| 512 | 1000 | 133349 | 37920 | 133.349000 | 37.920000 | 3.661679 | 12.876615 | 3.516588 |
| 1472 | 1000 | 382195 | 105118 | 382.195000 | 105.118000 | 3.673017 | 13.354598 | 3.635866 |

Summary: min speedup `1.541575x`, max speedup `3.635866x`, avg speedup `2.774654x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 2660 | 2455 | 2.660000 | 2.455000 | 5.736387 | 6.215393 | 1.083503 |
| 32 | 1000 | 3933 | 2861 | 3.933000 | 2.861000 | 7.759364 | 10.666752 | 1.374694 |
| 128 | 1000 | 11574 | 5279 | 11.574000 | 5.279000 | 10.546943 | 23.123757 | 2.192461 |
| 512 | 1000 | 42139 | 14891 | 42.139000 | 14.891000 | 11.587395 | 32.790360 | 2.829830 |
| 1472 | 1000 | 118550 | 39001 | 118.550000 | 39.001000 | 11.841490 | 35.994169 | 3.039666 |

Summary: min speedup `1.083503x`, max speedup `3.039666x`, avg speedup `2.104031x`.
