# Shadow Mirror Soak Summary

- Result: `FAIL`
- Mode: `sd cold-start soak`
- AssumeRunning: `False`
- ColdStart: `True`
- Boot evidence found: `False`
- Target IP: `192.168.1.20`
- Source IP: `192.168.1.11`
- Session ID: ``
- Binding ID: ``
- Duration requested: `1` minute(s)
- Cycle interval: `15` second(s)
- Cycles completed: `0`
- AES probes: `0`
- SM4 probes: `0`
- ACL probes: `0`
- Replay probes: `0`
- UART log: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\board_uart_boot_115200_20260402_213559.txt`
- JSON report: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\doc\reports\board_soak\shadow_mirror_20260402_213559\soak_report.json`
- First control success UTC: ``
- First data success UTC: ``

## Failure

- Reason: `Cold-start soak did not capture any UART boot data.`

## UART Warnings

- `UART log file was not created: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\board_uart_boot_115200_20260402_213559.txt`

## Cycle Summary

| Cycle | AES | SM4 | ACL Delta | Replay Delta | locked | authorized_mask | drop_replay | bind_fail | crypto_timeout | crypto_fail |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
