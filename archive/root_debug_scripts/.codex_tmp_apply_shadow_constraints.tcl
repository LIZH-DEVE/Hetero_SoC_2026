open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_postroute_physopt.dcp}
read_xdc {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/constraints/shadow_mirror_phasec_constraints.xdc}
puts "=== CLOCKS_AFTER_READ_XDC ==="
puts [join [lsort [get_clocks -quiet shadow_dna_clk_*]] "`n"]
puts "=== PBLOCKS_AFTER_READ_XDC ==="
puts [join [lsort [get_pblocks -quiet *]] "`n"]
puts "=== SAMPLE_PIN_CLOCKS ==="
set sample_pin [lindex [get_pins -hierarchical -quiet -filter {NAME =~ */u_device_dna_reader/dna_bit_count_reg[0]/C}] 0]
if {$sample_pin ne ""} {puts [join [get_clocks -quiet -of_objects $sample_pin] "`n"]}
close_design
exit
