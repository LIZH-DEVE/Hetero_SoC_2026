open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp}
set live [get_pblocks live_crypto_region]
set data [get_pblocks shadow_data_region]
set ctrl [get_pblocks shadow_ctrl_region]
puts "BEFORE=[report_drc -checks {FLBO-1 UTLZ-3} -return_string]"
delete_pblocks $live
puts "AFTER_DELETE_LIVE=[report_drc -checks {FLBO-1 UTLZ-3} -return_string]"
exit
