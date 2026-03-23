# Step 22: UART1 Readable Boot Log Closure

Date: 2026-03-18

## Scope

This step implemented the software-side closure work for readable UART1 boot logs:

- added UART1 bootstrap and FIFO pre-check to the bare-metal app
- fixed the authoritative UART1 register programming sequence in XSDB
- added a fixed host-side serial capture script
- tightened board smoke so XSDB script failures no longer look like success

This step finished with a readable board log after a board power cycle restored the PS debug path. The software-side changes are in place, built successfully, and verified on hardware.

## Files Changed

- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/src/main.c`
- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/download_bitstream.tcl`
- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/xsdb_check_status.tcl`
- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/run_board_smoke.ps1`
- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/capture_uart_boot_log.ps1`

## Bare-Metal App Changes

`main.c` now performs a minimal UART1 self-bootstrap before the normal banner:

- reprograms UART1 to a single preferred configuration
- reads `UART_SR` before and after bootstrap
- checks whether the TX FIFO is writable before printing startup text
- emits short ASCII lines first:
  - `BOOT UART1 OK`
  - `UART_BAUD=115200 ALT=230400`
  - `UART_SR_PRE=0x...`
  - `UART_SR=0x...`
  - `UART_TXEMPTY=...`
  - `STATUS=0x...`
  - `FINGERPRINT=0xACE`

The crypto test flow itself was preserved.

## UART Register Fixes

The authoritative UART programming flow is now explicitly:

- preferred host baud: `115200`
- fallback host baud: `230400`
- `UART_CLK_CTRL = 0x00002003`
- `BRGR = 62`
- `BDIV = 6`

Important correction:

- `BDIV` is programmed at `UART1_BASE + 0x34`
- it is **not** at `0x1C`

This was aligned to the Xilinx `xuartps_hw.h` register definition for PS UART.

## Host Capture Tool

Added:

- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/capture_uart_boot_log.ps1`

Usage:

```powershell
powershell -ExecutionPolicy Bypass -File D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\capture_uart_boot_log.ps1 `
  -ProgramBoard `
  -Port COM9 `
  -Baud 115200 `
  -TimeoutSeconds 10 `
  -XsdbPath D:\Xilinx\Vitis\2024.1\bin\xsdb.bat
```

Only use `-Baud 230400` if `115200` still produces unreadable bytes after board recovery.

## Build Result

The updated bare-metal application rebuilt successfully.

Command:

```powershell
$env:PATH='D:\Xilinx\Vitis\2024.1\gnu\aarch32\nt\gcc-arm-none-eabi\bin;' + $env:PATH
& 'D:\Xilinx\Vitis\2024.1\tps\win64\cmake-3.24.2\bin\cmake.exe' --build `
  'D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\crypto_test_app\build' `
  --target crypto_test_app.elf
```

## Smoke Driver Hardening

`run_board_smoke.ps1` now captures XSDB stdout/stderr and treats these as real failures:

- `AHB AP transaction error`
- `Context does not support memory read`
- `no targets found`
- `Socket bind error`
- `FAIL:`

This change matters because XSDB frequently returned exit code `0` even when Tcl scripts clearly failed.

## Hardware Verification Result

After a board power cycle, targets recovered as:

- `APU`
- `ARM Cortex-A9 MPCore #0 (Running)`
- `ARM Cortex-A9 MPCore #1 (Running)`
- `xc7z020`

`download_bitstream.tcl` was adjusted to accept `APU` as the PS-stage target, while still using `Cortex-A9 MPCore #0` for ELF download and status access.

Fresh board smoke succeeded again:

- `STATUS = 0xACE00447`
- `Hardware Fingerprint = 0xACE`

## UART Capture Result

The preferred host baud `115200` is now confirmed as the correct setting. No `230400` fallback was needed.

Three independent board runs produced readable UART logs:

- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/board_uart_boot_115200_20260318_090749.txt`
- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/board_uart_boot_115200_20260318_090848.txt`
- `D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/board_uart_boot_115200_20260318_090944.txt`

The captured logs include the intended ASCII startup lines:

- `BOOT UART1 OK`
- `UART_BAUD=115200 ALT=230400`
- `UART_SR_PRE=0x0000000A`
- `UART_SR=0x0000000A`
- `UART_TXEMPTY=1`
- `STATUS=0xACE00403`
- `FINGERPRINT=0xACE`

The same captures also include readable AES, SM4, and security test output.

## Current Acceptance State

### Closed in software

- UART1 bootstrap added to the application
- FIFO pre-check added before startup printing
- preferred/fallback baud policy fixed to `115200` then `230400`
- host capture script added
- smoke script now detects XSDB failures correctly

### Closed in hardware

- readable `COM9` boot log capture at `115200`
- repeated 3x board confirmation run

## Fixed Operating Procedure

Use this command for future UART boot-log collection:

```powershell
powershell -ExecutionPolicy Bypass -File D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\capture_uart_boot_log.ps1 `
  -ProgramBoard `
  -Port COM9 `
  -Baud 115200 `
  -TimeoutSeconds 12 `
  -XsdbPath D:\Xilinx\Vitis\2024.1\bin\xsdb.bat
```

Only use `230400` if a future board session regresses back to unreadable UART bytes.
