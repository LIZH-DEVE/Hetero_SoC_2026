# Phase C Board Benchmark Summary

Board-first acceptance source: AX7020 board UDP BENCH control responses.

- Target IP: `192.168.1.20`
- Source IP: `192.168.1.11`
- Control port: `4662`
- Repeats per length: `8`

PS software baseline: same-board software path measured by `gateway_sw_encrypt_buffer()`.
Hardware speedup vs PS software: same-board hardware path measured by `gateway_hw_encrypt_buffer_sync()`.
Target speedup gate: average speedup per algorithm must be `>= 1.000000x`.
Short payload note: `16B` and `32B` rows may remain `<1.0x`; failure should be judged on average result, not isolated short-packet rows.
Target result: `FAIL`

## AES

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 8 | 41 | 51 | 5.125000 | 6.375000 | 2.977325 | 2.393536 | 0.803922 |
| 32 | 8 | 74 | 88 | 9.250000 | 11.000000 | 3.299198 | 2.774325 | 0.840909 |
| 128 | 8 | 275 | 330 | 34.375000 | 41.250000 | 3.551136 | 2.959280 | 0.833333 |
| 512 | 8 | 1080 | 1298 | 135.000000 | 162.250000 | 3.616898 | 3.009438 | 0.832049 |
| 1472 | 8 | 3094 | 3719 | 386.750000 | 464.875000 | 3.629757 | 3.019755 | 0.831944 |

Summary: min speedup `0.803922x`, max speedup `0.840909x`, avg speedup `0.828431x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 8 | 19 | 44 | 2.375000 | 5.500000 | 6.424753 | 2.774325 | 0.431818 |
| 32 | 8 | 27 | 76 | 3.375000 | 9.500000 | 9.042245 | 3.212377 | 0.355263 |
| 128 | 8 | 83 | 283 | 10.375000 | 35.375000 | 11.765813 | 3.450751 | 0.293286 |
| 512 | 8 | 309 | 1113 | 38.625000 | 139.125000 | 12.641586 | 3.509659 | 0.277628 |
| 1472 | 8 | 873 | 3186 | 109.125000 | 398.250000 | 12.864225 | 3.524943 | 0.274011 |

Summary: min speedup `0.274011x`, max speedup `0.431818x`, avg speedup `0.326401x`.
