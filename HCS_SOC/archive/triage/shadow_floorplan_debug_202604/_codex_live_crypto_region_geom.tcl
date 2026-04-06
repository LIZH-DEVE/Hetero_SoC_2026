open_checkpoint D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp
set fp [open "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/_codex_live_crypto_region_geom.txt" w]
set pb [get_pblocks live_crypto_region]
puts $fp "PBLOCK_RANGE=[get_property GRID_RANGES $pb]"
puts $fp "SLICE_RANGE=[get_property RANGE $pb]"
puts $fp "SNAPPING_MODE=[get_property SNAPPING_MODE $pb]"
puts $fp "CONTAIN_ROUTING=[get_property CONTAIN_ROUTING $pb]"
foreach t {SLICE DSP48E1 RAMB18 RAMB36} {
  set sites [llength [get_sites -quiet -of_objects $pb -filter "SITE_TYPE == $t"]]
  puts $fp "$t=$sites"
}
close $fp
exit
