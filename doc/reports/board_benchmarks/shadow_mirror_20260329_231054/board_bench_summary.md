# Phase C Board Benchmark Summary

Board-first acceptance source: AX7020 board UDP BENCH control responses.

- Target IP: `192.168.1.20`
- Source IP: `192.168.1.11`
- Control port: `4662`
- Repeats per length: `8`

PS software baseline: same-board software path measured by `gateway_sw_encrypt_buffer()`.
Hardware speedup vs PS software: same-board hardware path measured by `gateway_hw_encrypt_buffer_sync()`.

## AES

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 8 | 41 | 75 | 5.125000 | 9.375000 | 2.977325 | 1.627604 | 0.546667 |
| 32 | 8 | 73 | 127 | 9.125000 | 15.875000 | 3.344392 | 1.922367 | 0.574803 |
| 128 | 8 | 271 | 440 | 33.875000 | 55.000000 | 3.603552 | 2.219460 | 0.615909 |
| 512 | 8 | 1067 | 1685 | 133.375000 | 210.625000 | 3.660965 | 2.318249 | 0.633234 |
| 1472 | 8 | 3055 | 4798 | 381.875000 | 599.750000 | 3.676095 | 2.340656 | 0.636724 |

Summary: min speedup `0.546667x`, max speedup `0.636724x`, avg speedup `0.601467x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 8 | 19 | 70 | 2.375000 | 8.750000 | 6.424753 | 1.743862 | 0.271429 |
| 32 | 8 | 28 | 115 | 3.500000 | 14.375000 | 8.719308 | 2.122962 | 0.243478 |
| 128 | 8 | 83 | 391 | 10.375000 | 48.875000 | 11.765813 | 2.497602 | 0.212276 |
| 512 | 8 | 306 | 1497 | 38.250000 | 187.125000 | 12.765523 | 2.609385 | 0.204409 |
| 1472 | 8 | 863 | 4262 | 107.875000 | 532.750000 | 13.013289 | 2.635023 | 0.202487 |

Summary: min speedup `0.202487x`, max speedup `0.271429x`, avg speedup `0.226816x`.
