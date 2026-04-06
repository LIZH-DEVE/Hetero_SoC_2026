AX7020 Repo-Owned design_1 UART Baseline

Purpose:
- Repo-owned board startup baseline derived from the current Vivado project.
- Validates the repo's own design_1 handoff chain before any DMA board image is tested.

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from the current design_1_wrapper.xsa
2. fresh design_1_wrapper.bit extracted from that same XSA
3. repo-owned UART baseline application ELF

Fresh source chain:
- Vivado project: HCS_SOC.xpr
- XSA export: design_1_wrapper.xsa via export_design1_wrapper_xsa.ps1 / export_xsa.tcl
- XSCT platform workspace: repo_design1_uart_baseline_xsct\workspace
- FSBL path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\repo_design1_uart_baseline_xsct\workspace\ax7020_repo_design1_uart_platform\zynq_fsbl\fsbl.elf
- Bitstream path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\repo_design1_uart_baseline_xsct\xsa_extract\design_1_wrapper.bit
- Platform SW dir: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\repo_design1_uart_baseline_xsct\workspace\ax7020_repo_design1_uart_platform\zynq_fsbl\zynq_fsbl_bsp\ps7_cortexa9_0
- App ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_repo_design1_uart_baseline_app\build\ax7020_repo_design1_uart_baseline_app.elf
- Timing summary: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\HCS_SOC.runs\HCS_SOC.runs\impl_1\design_1_wrapper_timing_summary_postroute_physopted.rpt
- Timing status:
  WNS = 4.117 ns
  TNS = 0 ns
  setup failing endpoints = 0
  WHS = 0.02 ns
  THS = 0 ns
  hold failing endpoints = 0
- SHA256: E923B2A932B9C3AE7B4743F6E89426286195C383DAC96259FF6D39027E40CD71

Expected board-side behavior:
- UART prints:
  REPO DESIGN1 UART BASELINE
  UART1 OK
  FRESH_XSA_FSBL_CHAIN
  REPO_HEARTBEAT N
