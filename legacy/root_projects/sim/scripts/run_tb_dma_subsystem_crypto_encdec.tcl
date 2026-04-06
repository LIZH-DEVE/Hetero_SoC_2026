# Batch simulation script for tb_dma_subsystem_crypto_encdec
# Usage:
#   vivado -mode batch -source sim/scripts/run_tb_dma_subsystem_crypto_encdec.tcl

set root_dir [file normalize [file join [file dirname [info script]] .. ..]]
set out_dir  [file normalize [file join $root_dir sim_output tb_dma_subsystem_crypto_encdec]]

file mkdir $out_dir
cd $out_dir

puts "=============================================="
puts "Running tb_dma_subsystem_crypto_encdec"
puts "Root: $root_dir"
puts "Out : $out_dir"
puts "=============================================="

proc compile_sv {f} {
    puts "xvlog -sv $f"
    xvlog -sv $f
}

proc compile_v {f} {
    puts "xvlog $f"
    xvlog $f
}

# Core utility files
compile_sv [file join $root_dir rtl inc sync_fifo.sv]
compile_sv [file join $root_dir rtl core gearbox_128_to_32.sv]

# Crypto files (.v first, then .sv)
foreach f [lsort [glob -nocomplain [file join $root_dir rtl core crypto *.v]]] {
    compile_v $f
}
compile_sv [file join $root_dir rtl core crypto crypto_bridge_top.sv]

# DMA / CSR / PBM
compile_sv [file join $root_dir rtl core axil_csr.sv]
compile_sv [file join $root_dir rtl core pbm pbm_controller.sv]
compile_sv [file join $root_dir rtl core dma dma_master_engine.sv]
compile_sv [file join $root_dir rtl core dma dma_s2mm_mm2s_engine.sv]
compile_sv [file join $root_dir rtl core dma dma_desc_fetcher.sv]

# Top and testbench
compile_sv [file join $root_dir rtl top dma_subsystem.sv]
compile_sv [file join $root_dir tb tests crypto_vectors_pkg.sv]
compile_sv [file join $root_dir tb tests tb_dma_subsystem_crypto_encdec.sv]

# Elaborate
puts "Elaborating..."
xelab -debug typical -relax -snapshot tb_dma_subsystem_crypto_encdec_sim \
    work.tb_dma_subsystem_crypto_encdec \
    -log elaborate.log

# Simulate
puts "Simulating..."
xsim tb_dma_subsystem_crypto_encdec_sim -runall -log simulate.log

puts "=============================================="
puts "Done."
puts "Simulation log : [file join $out_dir simulate.log]"
puts "TB report file : [file join $out_dir tb_dma_subsystem_crypto_encdec_report.log]"
puts "=============================================="
