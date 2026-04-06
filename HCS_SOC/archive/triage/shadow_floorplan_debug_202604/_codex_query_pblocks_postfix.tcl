open_checkpoint "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp"
foreach pb [list live_crypto_region shadow_data_region shadow_ctrl_region] {
  puts "PBEGIN:$pb"
  puts "RANGE=[get_property RANGE [get_pblocks $pb]]"
  puts "SLICE=[get_property GRID_RANGES.SLICE [get_pblocks $pb]]"
  puts "RAMB18=[get_property GRID_RANGES.RAMB18 [get_pblocks $pb]]"
  puts "RAMB36=[get_property GRID_RANGES.RAMB36 [get_pblocks $pb]]"
  puts "PEND:$pb"
}
close_design
