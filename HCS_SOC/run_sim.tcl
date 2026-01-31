# Vivado Simulation Script
# Open project
open_project HCS_SOC.xpr

# Reset simulation
reset_sim

# Set simulation top
set_property top tb_crypto_dma_subsystem [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Launch simulation
launch_simulation
