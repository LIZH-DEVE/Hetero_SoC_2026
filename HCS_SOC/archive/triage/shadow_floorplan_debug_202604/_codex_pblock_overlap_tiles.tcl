open_checkpoint "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp"
set live_tiles [lsort [get_tiles -quiet -of_objects [get_pblocks live_crypto_region]]]
set data_tiles [lsort [get_tiles -quiet -of_objects [get_pblocks shadow_data_region]]]
set overlap {}
foreach t $live_tiles {
  if {[lsearch -exact $data_tiles $t] >= 0} {lappend overlap $t}
}
puts "LIVE_TILE_COUNT=[llength $live_tiles]"
puts "DATA_TILE_COUNT=[llength $data_tiles]"
puts "OVERLAP_TILE_COUNT=[llength $overlap]"
puts "OVERLAP_TILES=[join $overlap { }]"
close_design
