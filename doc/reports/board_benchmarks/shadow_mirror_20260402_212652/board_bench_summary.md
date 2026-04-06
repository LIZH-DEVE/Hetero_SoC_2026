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
| 16 | 1000 | 4899 | 3186 | 4.899000 | 3.186000 | 3.114674 | 4.789325 | 1.537665 |
| 32 | 1000 | 9039 | 4293 | 9.039000 | 4.293000 | 3.376212 | 7.108683 | 2.105521 |
| 128 | 1000 | 33807 | 11050 | 33.807000 | 11.050000 | 3.610800 | 11.047087 | 3.059457 |
| 512 | 1000 | 132880 | 37920 | 132.880000 | 37.920000 | 3.674603 | 12.876615 | 3.504219 |
| 1472 | 1000 | 380826 | 105118 | 380.826000 | 105.118000 | 3.686220 | 13.354598 | 3.622843 |

Summary: min speedup `1.537665x`, max speedup `3.622843x`, avg speedup `2.765941x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 2641 | 2455 | 2.641000 | 2.455000 | 5.777656 | 6.215393 | 1.075764 |
| 32 | 1000 | 3935 | 2862 | 3.935000 | 2.862000 | 7.755420 | 10.663025 | 1.374913 |
| 128 | 1000 | 11585 | 5279 | 11.585000 | 5.279000 | 10.536928 | 23.123757 | 2.194544 |
| 512 | 1000 | 42185 | 14892 | 42.185000 | 14.892000 | 11.574760 | 32.788158 | 2.832729 |
| 1472 | 1000 | 118688 | 38995 | 118.688000 | 38.995000 | 11.827721 | 35.999707 | 3.043672 |

Summary: min speedup `1.075764x`, max speedup `3.043672x`, avg speedup `2.104324x`.
