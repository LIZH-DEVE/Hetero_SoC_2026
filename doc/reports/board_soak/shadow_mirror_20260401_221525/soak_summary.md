# Shadow Mirror JTAG Soak Summary

- Result: `FAIL`
- Mode: `mixed soak`
- AssumeRunning: `True`
- Target IP: `192.168.1.20`
- Source IP: `192.168.1.11`
- Session ID: `0x00000007`
- Binding ID: `0xc4ba0c4b`
- Duration requested: `1` minute(s)
- Cycle interval: `15` second(s)
- Cycles completed: `5`
- AES probes: `5`
- SM4 probes: `5`
- ACL probes: `0`
- Replay probes: `0`
- UART log: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\board_uart_boot_115200_20260401_221525.txt`
- JSON report: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\doc\reports\board_soak\shadow_mirror_20260401_221525\soak_report.json`

## Failure

- Reason: `UART log file was not created: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\board_uart_boot_115200_20260401_221525.txt`

## Cycle Summary

| Cycle | AES | SM4 | ACL Delta | Replay Delta | locked | authorized_mask | drop_replay | bind_fail | crypto_timeout | crypto_fail |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 2 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 3 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 4 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
| 5 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
