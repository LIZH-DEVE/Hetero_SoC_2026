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
| 16 | 1000 | 4895 | 3343 | 4.895000 | 3.343000 | 3.117219 | 4.564400 | 1.464254 |
| 32 | 1000 | 9051 | 4459 | 9.051000 | 4.459000 | 3.371736 | 6.844041 | 2.029827 |
| 128 | 1000 | 33810 | 11217 | 33.810000 | 11.217000 | 3.610480 | 10.882617 | 3.014175 |
| 512 | 1000 | 132847 | 38103 | 132.847000 | 38.103000 | 3.675516 | 12.814772 | 3.486523 |
| 1472 | 1000 | 380702 | 105300 | 380.702000 | 105.300000 | 3.687421 | 13.331516 | 3.615404 |

Summary: min speedup `1.464254x`, max speedup `3.615404x`, avg speedup `2.722037x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 2642 | 2604 | 2.642000 | 2.604000 | 5.775469 | 5.859750 | 1.014593 |
| 32 | 1000 | 3938 | 3013 | 3.938000 | 3.013000 | 7.749512 | 10.128635 | 1.307003 |
| 128 | 1000 | 11587 | 5460 | 11.587000 | 5.460000 | 10.535109 | 22.357200 | 2.122161 |
| 512 | 1000 | 42188 | 15045 | 42.188000 | 15.045000 | 11.573937 | 32.454719 | 2.804121 |
| 1472 | 1000 | 118691 | 39045 | 118.691000 | 39.045000 | 11.827422 | 35.953607 | 3.039851 |

Summary: min speedup `1.014593x`, max speedup `3.039851x`, avg speedup `2.057546x`.
