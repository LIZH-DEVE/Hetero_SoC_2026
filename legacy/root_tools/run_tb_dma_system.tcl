# Vivado TCL Script for tb_dma_system Verification
# Usage: vivado -mode batch -source run_tb_dma_system.tcl

# 1. Define Paths
set proj_dir "D:/FPGAhanjia/Hetero_SoC_2026"
set sim_dir "$proj_dir/sim_output"

# Create output directory
file mkdir $sim_dir
cd $sim_dir

# 2. Compile Design Sources (Order Matters!)
# Core Utilities
exec xvlog -sv "$proj_dir/rtl/core/utils/sync_fifo.sv"
exec xvlog -sv "$proj_dir/rtl/core/utils/gearbox_128_to_32.sv"

# Crypto Cores
exec xvlog -sv "$proj_dir/rtl/core/crypto/aes_core.sv"
exec xvlog -sv "$proj_dir/rtl/core/crypto/sm4_top.sv"
exec xvlog -sv "$proj_dir/rtl/core/crypto/crypto_bridge_top.sv"

# DMA & System Components
exec xvlog -sv "$proj_dir/rtl/core/axil_csr.sv"
exec xvlog -sv "$proj_dir/rtl/core/dma/dma_master_engine.sv"
exec xvlog -sv "$proj_dir/rtl/core/dma/dma_s2mm_mm2s_engine.sv"
exec xvlog -sv "$proj_dir/rtl/core/dma/dma_desc_fetcher.sv"
exec xvlog -sv "$proj_dir/rtl/core/pbm/pbm_controller.sv"
exec xvlog -sv "$proj_dir/rtl/top/dma_subsystem.sv"

# 3. Compile Testbench
exec xvlog -sv "$proj_dir/tb/tests/tb_dma_system.sv"

# 4. Elaborate
# Note: glbl is needed for Verilog simulation usually, but if not using Xilinx IP models it might be skippable.
# However, for safety, let's include it if present in standard lib, or omit if pure RTL.
# Trying without glbl first as we are testing pure RTL logic here mostly.
exec xelab -debug typical -top tb_dma_system -snapshot tb_dma_system_snap

# 5. Simulate
exec xsim tb_dma_system_snap -R > simulation_output.log

# 6. Check for Success
puts "Simulation Complete. Checking results..."
set fp [open "simulation_output.log" r]
set file_data [read $fp]
close $fp

if {[string match "*Performance Results*" $file_data]} {
    puts "Found Performance Results!"
    # Print the relevant section
    regexp {=== Performance Results ===.*Throughput.*Sim Cycles.*cycles} $file_data match
    puts $match
} else {
    puts "Error: Performance Results not found in log."
}
