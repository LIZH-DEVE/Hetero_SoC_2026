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
| 16 | 1000 | 4914 | 3181 | 4.914000 | 3.181000 | 3.105167 | 4.796853 | 1.544797 |
| 32 | 1000 | 9059 | 4293 | 9.059000 | 4.293000 | 3.368758 | 7.108683 | 2.110179 |
| 128 | 1000 | 33917 | 11050 | 33.917000 | 11.050000 | 3.599089 | 11.047087 | 3.069412 |
| 512 | 1000 | 133350 | 37921 | 133.350000 | 37.921000 | 3.661652 | 12.876276 | 3.516521 |
| 1472 | 1000 | 382195 | 105120 | 382.195000 | 105.120000 | 3.673017 | 13.354344 | 3.635797 |

Summary: min speedup `1.544797x`, max speedup `3.635797x`, avg speedup `2.775341x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 2638 | 2452 | 2.638000 | 2.452000 | 5.784226 | 6.222997 | 1.075856 |
| 32 | 1000 | 3934 | 2859 | 3.934000 | 2.859000 | 7.757391 | 10.674214 | 1.376006 |
| 128 | 1000 | 11574 | 5278 | 11.574000 | 5.278000 | 10.546943 | 23.128138 | 2.192876 |
| 512 | 1000 | 42138 | 14891 | 42.138000 | 14.891000 | 11.587670 | 32.790360 | 2.829763 |
| 1472 | 1000 | 118551 | 39000 | 118.551000 | 39.000000 | 11.841390 | 35.995092 | 3.039769 |

Summary: min speedup `1.075856x`, max speedup `3.039769x`, avg speedup `2.102854x`.
