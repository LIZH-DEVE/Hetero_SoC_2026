open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_postroute_physopt.dcp}
puts "=== CLOCKS ==="
puts [join [lsort [get_clocks -quiet shadow_dna_clk_*]] "`n"]
puts "=== PBLOCKS ==="
puts [join [lsort [get_pblocks -quiet *]] "`n"]
puts "=== DNA_Q_PINS ==="
puts [join [lsort [get_pins -hierarchical -quiet -filter {NAME =~ */u_device_dna_reader/dna_clk_reg/Q}]] "`n"]
puts "=== DNA_REG_CLOCK_OBJECTS ==="
set sample_pin [lindex [get_pins -hierarchical -quiet -filter {NAME =~ */u_device_dna_reader/dna_bit_count_reg[0]/C}] 0]
if {$sample_pin ne ""} {
  puts "sample_pin=$sample_pin"
  puts [join [get_clocks -quiet -of_objects $sample_pin] "`n"]
} else {
  puts "sample_pin=<none>"
}
puts "=== PBLOCK_TARGET_DMA ==="
puts [join [get_cells -hierarchical -quiet udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/i_hybrid_dma] "`n"]
puts "=== PBLOCK_TARGET_CRYPTO ==="
puts [join [get_cells -hierarchical -quiet udp_gateway_shadow_mirror_i/crypto_accel_axi_0/inst/u_design1_crypto_accel_axi] "`n"]
close_design
exit
