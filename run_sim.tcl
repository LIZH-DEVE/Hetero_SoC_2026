# Vivado TCL script to compile and run simulation

# Set project directory
set proj_dir "D:/FPGAhanjia/Hetero_SoC_2026/HCS_SOC"
cd $proj_dir

# Read and compile all design files
xvlog -sv -prj HCS_SOC.sim/sim_1/behav/xsim/tb_crypto_dma_subsystem_vlog.prj
xelab -debug typical -relax -snapshot tb_crypto_dma_subsystem_behav xil_defaultlib.tb_crypto_dma_subsystem xil_defaultlib.glbl -log elaborate.log

# Run simulation
xsim tb_crypto_dma_subsystem_behav -runall -log simulate.log
