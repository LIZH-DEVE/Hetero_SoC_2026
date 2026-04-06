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
| 16 | 1000 | 4914 | 3186 | 4.914000 | 3.186000 | 3.105167 | 4.789325 | 1.542373 |
| 32 | 1000 | 9059 | 4293 | 9.059000 | 4.293000 | 3.368758 | 7.108683 | 2.110179 |
| 128 | 1000 | 33917 | 11050 | 33.917000 | 11.050000 | 3.599089 | 11.047087 | 3.069412 |
| 512 | 1000 | 133350 | 37920 | 133.350000 | 37.920000 | 3.661652 | 12.876615 | 3.516614 |
| 1472 | 1000 | 381931 | 105120 | 381.931000 | 105.120000 | 3.675556 | 13.354344 | 3.633286 |

Summary: min speedup `1.542373x`, max speedup `3.633286x`, avg speedup `2.774373x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 2638 | 2455 | 2.638000 | 2.455000 | 5.784226 | 6.215393 | 1.074542 |
| 32 | 1000 | 3933 | 2861 | 3.933000 | 2.861000 | 7.759364 | 10.666752 | 1.374694 |
| 128 | 1000 | 11574 | 5279 | 11.574000 | 5.279000 | 10.546943 | 23.123757 | 2.192461 |
| 512 | 1000 | 42138 | 14891 | 42.138000 | 14.891000 | 11.587670 | 32.790360 | 2.829763 |
| 1472 | 1000 | 118815 | 39000 | 118.815000 | 39.000000 | 11.815079 | 35.995092 | 3.046538 |

Summary: min speedup `1.074542x`, max speedup `3.046538x`, avg speedup `2.103600x`.
