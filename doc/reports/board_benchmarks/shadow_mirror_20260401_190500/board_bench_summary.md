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
| 16 | 1000 | 4938 | 3343 | 4.938000 | 3.343000 | 3.090075 | 4.564400 | 1.477116 |
| 32 | 1000 | 9077 | 4458 | 9.077000 | 4.458000 | 3.362078 | 6.845576 | 2.036115 |
| 128 | 1000 | 33835 | 11216 | 33.835000 | 11.216000 | 3.607812 | 10.883587 | 3.016673 |
| 512 | 1000 | 132873 | 38103 | 132.873000 | 38.103000 | 3.674797 | 12.814772 | 3.487206 |
| 1472 | 1000 | 380728 | 105298 | 380.728000 | 105.298000 | 3.687169 | 13.331769 | 3.615719 |

Summary: min speedup `1.477116x`, max speedup `3.615719x`, avg speedup `2.726566x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 2635 | 2603 | 2.635000 | 2.603000 | 5.790812 | 5.862001 | 1.012294 |
| 32 | 1000 | 3927 | 3012 | 3.927000 | 3.012000 | 7.771219 | 10.131998 | 1.303785 |
| 128 | 1000 | 11577 | 5461 | 11.577000 | 5.461000 | 10.544209 | 22.353106 | 2.119941 |
| 512 | 1000 | 42178 | 15046 | 42.178000 | 15.046000 | 11.576681 | 32.452562 | 2.803270 |
| 1472 | 1000 | 118680 | 39046 | 118.680000 | 39.046000 | 11.828519 | 35.952686 | 3.039492 |

Summary: min speedup `1.012294x`, max speedup `3.039492x`, avg speedup `2.055756x`.
