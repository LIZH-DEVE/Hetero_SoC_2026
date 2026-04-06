open_checkpoint D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp
foreach pb {live_crypto_region shadow_data_region shadow_ctrl_region} {
  puts "PBLOCK=$pb"
  puts "RANGE=[get_property GRID_RANGES [get_pblocks $pb]]"
  puts "CELLS=[llength [get_cells -quiet -of_objects [get_pblocks $pb]]]"
}
close_design
exit
