# Phase C Board Benchmark Summary

Board-first acceptance source: AX7020 board Stage 2 SG proof UART log.

- Target IP: `uart-proof`
- Source IP: `uart-proof`
- Control port: `0`
- Repeats per length: `1000`

PS software baseline: same-board software path measured by `gateway_sw_encrypt_buffer()`.
Hardware speedup vs PS software: same-board descriptor-driven DMA/crypto path measured by the Stage 2 proof image.
Target speedup gate: average speedup per algorithm must be `>= 1.000000x`.
Short payload note: `16B` and `32B` rows may remain `<1.0x`; failure should be judged on average result, not isolated short-packet rows.
Target result: `FAIL`

## AES

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 5251 | 4551 | 5.251000 | 4.551000 | 2.905883 | 3.352843 | 1.153812 |
| 32 | 1000 | 9757 | 6242 | 9.757000 | 6.242000 | 3.127762 | 4.889071 | 1.563121 |
| 128 | 1000 | 36550 | 16681 | 36.550000 | 16.681000 | 3.339817 | 7.317925 | 2.191116 |
| 512 | 1000 | 143722 | 58492 | 143.722000 | 58.492000 | 3.397401 | 8.347830 | 2.457122 |
| 1472 | 1000 | 410860 | 162335 | 410.860000 | 162.335000 | 3.416757 | 8.647603 | 2.530939 |

Diagnostics:
- Hardware execution mode: `single-launch SG batch`
- Descriptor count: `1000`
- Doorbell count: `1`
- Last descriptor poll count: `562530`
- Actual length mismatch count: `0`

Summary: min speedup `1.153812x`, max speedup `2.530939x`, avg speedup `1.979222x`.

## SM4

| Length (B) | Repeats | SW Total (us) | HW Total (us) | SW Avg Latency (us) | HW Avg Latency (us) | SW Throughput (MB/s) | HW Throughput (MB/s) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1000 | 2216 | 3901 | 2.216000 | 3.901000 | 6.885735 | 3.911507 | 0.568059 |
| 32 | 1000 | 3389 | 5510 | 3.389000 | 5.510000 | 9.004892 | 5.538580 | 0.615064 |
| 128 | 1000 | 10374 | 15606 | 10.374000 | 15.606000 | 11.766947 | 7.822012 | 0.664744 |
| 512 | 1000 | 38315 | 57525 | 38.315000 | 57.525000 | 12.743867 | 8.488157 | 0.666058 |
| 1472 | 1000 | 108155 | 161514 | 108.155000 | 161.514000 | 12.979600 | 8.691560 | 0.669632 |

Diagnostics:
- Hardware execution mode: `single-launch SG batch`
- Descriptor count: `1000`
- Doorbell count: `1`
- Last descriptor poll count: `559522`
- Actual length mismatch count: `0`

Summary: min speedup `0.568059x`, max speedup `0.669632x`, avg speedup `0.636712x`.
