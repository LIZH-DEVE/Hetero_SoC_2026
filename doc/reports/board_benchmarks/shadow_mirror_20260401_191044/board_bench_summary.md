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
| 16 | 1000 | 4937 | 3344 | 4.937000 | 3.344000 | 3.090701 | 4.563035 | 1.476376 |
| 32 | 1000 | 9077 | 4457 | 9.077000 | 4.457000 | 3.362078 | 6.847112 | 2.036572 |
| 128 | 1000 | 33835 | 11216 | 33.835000 | 11.216000 | 3.607812 | 10.883587 | 3.016673 |
| 512 | 1000 | 132872 | 38102 | 132.872000 | 38.102000 | 3.674824 | 12.815108 | 3.487271 |
| 1472 | 1000 | 380728 | 105301 | 380.728000 | 105.301000 | 3.687169 | 13.331389 | 3.615616 |

Summary: min speedup `1.476376x`, max speedup `3.615616x`, avg speedup `2.726501x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 2634 | 2604 | 2.634000 | 2.604000 | 5.793010 | 5.859750 | 1.011521 |
| 32 | 1000 | 3927 | 3013 | 3.927000 | 3.013000 | 7.771219 | 10.128635 | 1.303352 |
| 128 | 1000 | 11577 | 5460 | 11.577000 | 5.460000 | 10.544209 | 22.357200 | 2.120330 |
| 512 | 1000 | 42178 | 15046 | 42.178000 | 15.046000 | 11.576681 | 32.452562 | 2.803270 |
| 1472 | 1000 | 118679 | 39046 | 118.679000 | 39.046000 | 11.828618 | 35.952686 | 3.039466 |

Summary: min speedup `1.011521x`, max speedup `3.039466x`, avg speedup `2.055588x`.
