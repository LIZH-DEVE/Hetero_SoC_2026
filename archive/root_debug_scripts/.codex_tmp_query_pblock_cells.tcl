open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_postroute_physopt.dcp}
puts "=== HYBRID_MATCHES ==="
puts [join [lsort [get_cells -hierarchical -quiet -filter {NAME =~ *i_hybrid_dma*}]] "`n"]
puts "=== CRYPTO_MATCHES ==="
puts [join [lsort [get_cells -hierarchical -quiet -filter {NAME =~ *u_design1_crypto_accel_axi*}]] "`n"]
close_design
exit
