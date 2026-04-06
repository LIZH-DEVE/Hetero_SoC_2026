AX7020 Low-LUT Raw-Copy DMA Smoke (No-Bit Diagnostic)

Purpose:
- Diagnostic image to separate bitstream-load failures from FSBL/app bring-up.
- Uses the same fresh raw-copy FSBL and the same raw-copy smoke app.
- Omits the PL bitstream on purpose.

Clean boot image structure:
1. [bootloader] fresh fsbl.elf generated from raw_copy_dma_wrapper.xsa
2. raw-copy smoke application ELF

Fresh source chain:
- XSA path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\raw_copy_dma_wrapper.xsa
- XSCT workspace: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_platform_xsct\workspace
- Platform name: ax7020_dma_raw_copy_platform
- FSBL path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_platform_xsct\workspace\ax7020_dma_raw_copy_platform\zynq_fsbl\fsbl.elf
- App API BSP root: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_platform_xsct\workspace\ax7020_dma_raw_copy_platform\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0
- App toolchain BSP root: same-platform zynq_fsbl_bsp if present, else explicit legacy fallback selected by build_ax7020_dma_raw_copy_smoke_app.ps1
- App ELF path: D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\ax7020_dma_raw_copy_smoke_app\build\ax7020_dma_raw_copy_smoke_app.elf
- SHA256: CB3938AF94CED98E805B834141AD66F200552D4F52B5FFB6A372352B5AF75A32

Expected board-side behavior:
- UART prints at least:
  RAWCOPY_STAGE INIT
