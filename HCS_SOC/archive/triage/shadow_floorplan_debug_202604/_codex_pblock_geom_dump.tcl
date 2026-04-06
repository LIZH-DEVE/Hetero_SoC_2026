open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp}
set live [get_pblocks live_crypto_region]
set data [get_pblocks shadow_data_region]
puts "LIVE_GRID=[get_property GRID_RANGES $live]"
puts "DATA_GRID=[get_property GRID_RANGES $data]"
puts "LIVE_RECTS=[get_property RECTANGLE_SITES $live]"
puts "DATA_RECTS=[get_property RECTANGLE_SITES $data]"
exit
