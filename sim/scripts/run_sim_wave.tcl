# Vivado TCL script to compile and run simulation with waveform

# Set project directory
set proj_dir "D:/FPGAhanjia/Hetero_SoC_2026/HCS_SOC"
cd $proj_dir

# Create directory for waveform
file mkdir waveform_db

# Elaborate design (assuming already compiled)
if {![file exists "HCS_SOC.sim/sim_1/behav/xsim/tb_crypto_dma_subsystem_behav.wdb"]} {
    exec "D:/Xilinx/Vivado/2024.1/bin/unwrapped/win64.o/xelab.exe" -debug typical -relax -snapshot tb_crypto_dma_subsystem_behav xil_defaultlib.tb_crypto_dma_subsystem xil_defaultlib.glbl -log elaborate_wave.log
}

# Run simulation and generate waveform
exec "D:/Xilinx/Vivado/2024.1/bin/unwrapped/win64.o/xsim.exe" tb_crypto_dma_subsystem_behav -gui -view wave.tcl -log simulate_wave.log

puts "Simulation complete. Waveform saved in wave.tcl"
