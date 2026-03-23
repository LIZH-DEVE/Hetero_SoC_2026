# XSDB one-shot bring-up script
# Usage inside xsdb: source D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/xsdb_run.tcl

connect

# Select Cortex-A9 #0
targets -set -nocase -filter {name =~ "arm*#0"}

# Full system reset (clears AXI/DDR state)
rst -system

# Program PL
fpga -f D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit

# Init PS/DDR
source D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/platform/hw/ps7_init.tcl
ps7_init
ps7_post_config

# Download and run ELF
# Update this path if your build output moves
set elf_path "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/build/crypto_test_app.elf"
dow $elf_path
con
