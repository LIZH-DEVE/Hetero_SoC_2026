# Day 17: Zero-Copy FastPath Test Script

# Add design sources
add_files -norecurse {
    rtl/core/fast_path.sv
}

# Add simulation sources
add_files -fileset sim_1 -norecurse {
    tb/tb_day17_fastpath.sv
}

# Set top module for simulation
set_property top tb_day17_fastpath [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sim_1

# Launch simulation
launch_simulation

# Run all
run all
