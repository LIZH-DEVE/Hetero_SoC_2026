# Simple script to run simulation and generate waveform

# Add all testbench and DUT signals to waveform
add_wave -radix hex /tb_crypto_dma_subsystem/u_dut/*
add_wave -radix hex /tb_crypto_dma_subsystem/u_dut/u_pbm/*
add_wave -radix hex /tb_crypto_dma_subsystem/u_dut/u_crypto_bridge/*
add_wave -radix hex /tb_crypto_dma_subsystem/u_dut/u_dma_engine/*
add_wave -radix hex /tb_crypto_dma_subsystem/u_dut/u_fetcher/*

# Run simulation
run all
