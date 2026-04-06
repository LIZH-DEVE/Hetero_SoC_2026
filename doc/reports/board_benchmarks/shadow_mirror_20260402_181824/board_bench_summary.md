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
| 16 | 1000 | 4899 | 3181 | 4.899000 | 3.181000 | 3.114674 | 4.796853 | 1.540082 |
| 32 | 1000 | 9039 | 4294 | 9.039000 | 4.294000 | 3.376212 | 7.107028 | 2.105030 |
| 128 | 1000 | 33807 | 11050 | 33.807000 | 11.050000 | 3.610800 | 11.047087 | 3.059457 |
| 512 | 1000 | 133143 | 37921 | 133.143000 | 37.921000 | 3.667345 | 12.876276 | 3.511062 |
| 1472 | 1000 | 380563 | 105118 | 380.563000 | 105.118000 | 3.688768 | 13.354598 | 3.620341 |

Summary: min speedup `1.540082x`, max speedup `3.620341x`, avg speedup `2.767194x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 2641 | 2454 | 2.641000 | 2.454000 | 5.777656 | 6.217925 | 1.076202 |
| 32 | 1000 | 3934 | 2858 | 3.934000 | 2.858000 | 7.757391 | 10.677949 | 1.376487 |
| 128 | 1000 | 11583 | 5279 | 11.583000 | 5.279000 | 10.538748 | 23.123757 | 2.194166 |
| 512 | 1000 | 42184 | 14891 | 42.184000 | 14.891000 | 11.575034 | 32.790360 | 2.832852 |
| 1472 | 1000 | 118686 | 38995 | 118.686000 | 38.995000 | 11.827921 | 35.999707 | 3.043621 |

Summary: min speedup `1.076202x`, max speedup `3.043621x`, avg speedup `2.104666x`.
