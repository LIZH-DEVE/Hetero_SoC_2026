# Day 17: FastPath Simulation with Vivado GUI Mode
# Create new project
create_project -force day17_fastprj ./HCS_SOC/day17_fastprj.xpr

# Set project properties
set_property part xc7z020clg400-1 [current_project]
set_property target_language Verilog [current_project]
set_property target_simulator XSim [current_project]

# Add design sources
add_files -norecurse {
    D:/FPGAhanjia/Hetero_SoC_2026/rtl/core/fast_path.sv
}

# Add simulation sources
add_files -fileset sim_1 -norecurse {
    D:/FPGAhanjia/Hetero_SoC_2026/tb/tb_day17_fastpath.sv
}

# Set top module for simulation
set_property top tb_day17_fastpath [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sim_1

# Set simulation properties
set_property -name {xsim.simulate.runtime} -value {100us} -objects [get_filesets sim_1]

# Launch simulation
launch_simulation

# Run all
run all
