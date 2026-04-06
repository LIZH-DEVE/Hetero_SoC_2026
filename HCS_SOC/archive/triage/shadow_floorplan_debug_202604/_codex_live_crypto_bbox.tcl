open_checkpoint D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp
set pb [get_pblocks live_crypto_region]
set fp [open "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/_codex_live_crypto_bbox.txt" w]
puts $fp "GRID_RANGES=[get_property GRID_RANGES $pb]"
puts $fp "SLICE_SITES=[join [lsort [get_sites -quiet -of_objects $pb -filter {SITE_TYPE =~ SLICE*}]] ","]"
puts $fp "RAMB36_SITES=[join [lsort [get_sites -quiet -of_objects $pb -filter {SITE_TYPE == RAMB36E1}]] ","]"
puts $fp "RAMB18_SITES=[join [lsort [get_sites -quiet -of_objects $pb -filter {SITE_TYPE == RAMB18E1}]] ","]"
puts $fp "DSP_SITES=[join [lsort [get_sites -quiet -of_objects $pb -filter {SITE_TYPE == DSP48E1}]] ","]"
close $fp
exit
