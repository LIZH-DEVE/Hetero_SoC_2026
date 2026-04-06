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
| 16 | 1000 | 4896 | 3344 | 4.896000 | 3.344000 | 3.116583 | 4.563035 | 1.464115 |
| 32 | 1000 | 9078 | 4458 | 9.078000 | 4.458000 | 3.361707 | 6.845576 | 2.036339 |
| 128 | 1000 | 33846 | 11215 | 33.846000 | 11.215000 | 3.606639 | 10.884558 | 3.017922 |
| 512 | 1000 | 132919 | 38102 | 132.919000 | 38.102000 | 3.673525 | 12.815108 | 3.488505 |
| 1472 | 1000 | 380864 | 105297 | 380.864000 | 105.297000 | 3.685853 | 13.331895 | 3.617045 |

Summary: min speedup `1.464115x`, max speedup `3.617045x`, avg speedup `2.724785x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 2635 | 2603 | 2.635000 | 2.603000 | 5.790812 | 5.862001 | 1.012294 |
| 32 | 1000 | 3927 | 3009 | 3.927000 | 3.009000 | 7.771219 | 10.142100 | 1.305085 |
| 128 | 1000 | 11577 | 5460 | 11.577000 | 5.460000 | 10.544209 | 22.357200 | 2.120330 |
| 512 | 1000 | 42178 | 15046 | 42.178000 | 15.046000 | 11.576681 | 32.452562 | 2.803270 |
| 1472 | 1000 | 118679 | 39047 | 118.679000 | 39.047000 | 11.828618 | 35.951766 | 3.039388 |

Summary: min speedup `1.012294x`, max speedup `3.039388x`, avg speedup `2.056073x`.
