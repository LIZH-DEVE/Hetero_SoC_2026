# Vivado clean and rebuild script
cd D:/FPGAhanjia/Hetero_SoC_2026/HCS_SOC

# Reset simulation
reset_sim

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Set simulation top as tb_crypto_dma_subsystem
set_property top tb_crypto_dma_subsystem [get_filesets sim_1]

# Launch simulation
launch_simulation
