open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp}
set live [get_pblocks live_crypto_region]
set data [get_pblocks shadow_data_region]
set ctrl [get_pblocks shadow_ctrl_region]
delete_pblocks $live
resize_pblock $data -remove [get_sites -of_objects $data]
resize_pblock $data -add {SLICE_X0Y0:SLICE_X113Y49 SLICE_X26Y50:SLICE_X95Y98 SLICE_X0Y100:SLICE_X95Y149 RAMB36_X3Y0:RAMB36_X5Y11}
puts "DATA_GRID=[get_property GRID_RANGES $data]"
set drc [report_drc -checks {FLBO-1 UTLZ-3} -return_string]
puts "HAS_FLBO=[expr {[regexp {FLBO-1} $drc] ? 1 : 0}]"
puts "HAS_UTLZ=[expr {[regexp {UTLZ-3} $drc] ? 1 : 0}]"
puts $drc
puts [report_utilization -pblocks $data -return_string]
exit
