open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp}
resize_pblock [get_pblocks live_crypto_region] -remove [get_sites -of_objects [get_pblocks live_crypto_region]]
resize_pblock [get_pblocks shadow_data_region] -remove [get_sites -of_objects [get_pblocks shadow_data_region]]
resize_pblock [get_pblocks live_crypto_region] -add {SLICE_X0Y100:SLICE_X79Y149 SLICE_X96Y100:SLICE_X113Y149 SLICE_X80Y51:SLICE_X95Y98}
resize_pblock [get_pblocks shadow_data_region] -add {SLICE_X0Y0:SLICE_X113Y49 SLICE_X26Y50:SLICE_X79Y98 RAMB36_X3Y0:RAMB36_X5Y11}
puts "LIVE=[get_property GRID_RANGES [get_pblocks live_crypto_region]]"
puts "DATA=[get_property GRID_RANGES [get_pblocks shadow_data_region]]"
set drc [report_drc -checks {FLBO-1 UTLZ-3} -return_string]
puts "HAS_FLBO=[expr {[regexp {FLBO-1} $drc] ? 1 : 0}]"
puts "HAS_UTLZ=[expr {[regexp {UTLZ-3} $drc] ? 1 : 0}]"
puts $drc
exit
