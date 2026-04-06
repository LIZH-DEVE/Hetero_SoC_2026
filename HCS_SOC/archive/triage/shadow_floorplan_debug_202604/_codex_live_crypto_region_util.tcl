open_checkpoint D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp
set fp [open "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/_codex_live_crypto_region_util.txt" w]
puts $fp "PBLOCK=[get_pblocks live_crypto_region]"
puts $fp "CELLS=[llength [get_cells -quiet -of_objects [get_pblocks live_crypto_region]]]"
report_utilization -pblocks [get_pblocks live_crypto_region] -file D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/_codex_live_crypto_region_util.rpt
report_utilization -pblocks [get_pblocks shadow_data_region] -file D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/_codex_shadow_data_region_util.rpt
report_utilization -pblocks [get_pblocks shadow_ctrl_region] -file D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/_codex_shadow_ctrl_region_util.rpt
puts $fp "DONE"
close $fp
exit
