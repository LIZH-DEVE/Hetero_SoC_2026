# Shadow Mirror Soak Summary

- Result: `PASS`
- Mode: `sd cold-start soak`
- AssumeRunning: `False`
- ColdStart: `True`
- Boot evidence found: `True`
- Boot evidence mode: `control_data_after_manual_power_cycle`
- Target IP: `192.168.1.20`
- Source IP: `192.168.1.11`
- Session ID: `0x00000001`
- Binding ID: `0xc4ba0c4b`
- Duration requested: `1` minute(s)
- Cycle interval: `15` second(s)
- Cycles completed: `1`
- AES probes: `1`
- SM4 probes: `1`
- ACL probes: `0`
- Replay probes: `0`
- UART log: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\board_uart_boot_115200_20260402_215550.txt`
- JSON report: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\doc\reports\board_soak\shadow_mirror_20260402_215550\soak_report.json`
- First control success UTC: `2026-04-02T13:56:37.3412379Z`
- First data success UTC: `2026-04-02T13:56:41.4906107Z`
- Boot evidence lines: `fallback control evidence: 2026-04-02T13:56:37.3412379Z; fallback data evidence: 2026-04-02T13:56:41.4906107Z`

## UART Warnings

- `Cold-start UART boot capture was empty; will require control/data fallback evidence.`
- `UART log file was not created: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\board_uart_boot_115200_20260402_215550.txt`

## Cycle Summary

| Cycle | AES | SM4 | ACL Delta | Replay Delta | locked | authorized_mask | drop_replay | bind_fail | crypto_timeout | crypto_fail |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | PASS | PASS | - | - | 0 | 3 | 0 | 0 | 0 | 0 |
