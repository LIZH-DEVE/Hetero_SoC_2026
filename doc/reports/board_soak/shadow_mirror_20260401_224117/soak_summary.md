# Shadow Mirror JTAG Soak Summary

- Result: `PASS`
- Mode: `mixed soak`
- AssumeRunning: `True`
- Target IP: `192.168.1.20`
- Source IP: `192.168.1.11`
- Session ID: `0x00000009`
- Binding ID: `0xc4ba0c4b`
- Duration requested: `30` minute(s)
- Cycle interval: `15` second(s)
- Cycles completed: `128`
- AES probes: `128`
- SM4 probes: `128`
- ACL probes: `12`
- Replay probes: `6`
- UART log: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\board_uart_boot_115200_20260401_224117.txt`
- JSON report: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\doc\reports\board_soak\shadow_mirror_20260401_224117\soak_report.json`

## UART Warnings

- `UART log file was not created: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\board_uart_boot_115200_20260401_224117.txt`

## Cycle Summary

| Cycle | AES | SM4 | ACL Delta | Replay Delta | locked | authorized_mask | drop_replay | bind_fail | crypto_timeout | crypto_fail |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 2 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 3 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 4 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 5 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 6 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 7 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 8 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 9 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 10 | PASS | PASS | 1 | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 11 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 12 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 13 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 14 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 15 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 16 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 17 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 18 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 19 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 20 | PASS | PASS | 1 | 1 | 0 | 3 | 1 | 0 | 0 | 0 |
| 21 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 22 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 23 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 24 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 25 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 26 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 27 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 28 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 29 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 30 | PASS | PASS | 1 | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 31 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 32 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 33 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 34 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 35 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 36 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 37 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 38 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 39 | PASS | PASS | - | - | 0 | 3 | 1 | 0 | 0 | 0 |
| 40 | PASS | PASS | 1 | 1 | 0 | 3 | 2 | 0 | 0 | 0 |
| 41 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 42 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 43 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 44 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 45 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 46 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 47 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 48 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 49 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 50 | PASS | PASS | 1 | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 51 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 52 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 53 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 54 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 55 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 56 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 57 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 58 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 59 | PASS | PASS | - | - | 0 | 3 | 2 | 0 | 0 | 0 |
| 60 | PASS | PASS | 1 | 1 | 0 | 3 | 3 | 0 | 0 | 0 |
| 61 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 62 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 63 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 64 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 65 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 66 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 67 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 68 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 69 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 70 | PASS | PASS | 1 | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 71 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 72 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 73 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 74 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 75 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 76 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 77 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 78 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 79 | PASS | PASS | - | - | 0 | 3 | 3 | 0 | 0 | 0 |
| 80 | PASS | PASS | 1 | 1 | 0 | 3 | 4 | 0 | 0 | 0 |
| 81 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 82 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 83 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 84 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 85 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 86 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 87 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 88 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 89 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 90 | PASS | PASS | 1 | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 91 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 92 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 93 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 94 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 95 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 96 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 97 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 98 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 99 | PASS | PASS | - | - | 0 | 3 | 4 | 0 | 0 | 0 |
| 100 | PASS | PASS | 1 | 1 | 0 | 3 | 5 | 0 | 0 | 0 |
| 101 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 102 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 103 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 104 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 105 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 106 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 107 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 108 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 109 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 110 | PASS | PASS | 1 | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 111 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 112 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 113 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 114 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 115 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 116 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 117 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 118 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 119 | PASS | PASS | - | - | 0 | 3 | 5 | 0 | 0 | 0 |
| 120 | PASS | PASS | 1 | 1 | 0 | 3 | 6 | 0 | 0 | 0 |
| 121 | PASS | PASS | - | - | 0 | 3 | 6 | 0 | 0 | 0 |
| 122 | PASS | PASS | - | - | 0 | 3 | 6 | 0 | 0 | 0 |
| 123 | PASS | PASS | - | - | 0 | 3 | 6 | 0 | 0 | 0 |
| 124 | PASS | PASS | - | - | 0 | 3 | 6 | 0 | 0 | 0 |
| 125 | PASS | PASS | - | - | 0 | 3 | 6 | 0 | 0 | 0 |
| 126 | PASS | PASS | - | - | 0 | 3 | 6 | 0 | 0 | 0 |
| 127 | PASS | PASS | - | - | 0 | 3 | 6 | 0 | 0 | 0 |
| 128 | PASS | PASS | - | - | 0 | 3 | 6 | 0 | 0 | 0 |
