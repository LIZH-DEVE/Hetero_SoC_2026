open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp}
puts "=== LIVE UTIL ==="
puts [report_utilization -pblocks [get_pblocks live_crypto_region] -return_string]
puts "=== DATA UTIL ==="
puts [report_utilization -pblocks [get_pblocks shadow_data_region] -return_string]
exit
