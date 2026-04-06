open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_postroute_physopt.dcp}
read_xdc {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/constraints/shadow_mirror_phasec_constraints.xdc}
puts "=== CLOCKS_AFTER_READ_XDC ==="
puts [join [lsort [get_clocks -quiet shadow_dna_clk*]] "`n"]
puts "=== PBLOCKS_AFTER_READ_XDC ==="
puts [join [lsort [get_pblocks -quiet *]] "`n"]
puts "=== CLOCK_ON_DNA_Q ==="
puts [join [get_clocks -quiet -of_objects [get_pins udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader/dna_clk_reg/Q]] "`n"]
close_design
exit
