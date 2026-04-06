open_checkpoint "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp"
set live_sites [lsort [get_sites -quiet -of_objects [get_pblocks live_crypto_region]]]
set data_sites [lsort [get_sites -quiet -of_objects [get_pblocks shadow_data_region]]]
set overlap {}
foreach s $live_sites {
  if {[lsearch -exact $data_sites $s] >= 0} {lappend overlap $s}
}
puts "LIVE_COUNT=[llength $live_sites]"
puts "DATA_COUNT=[llength $data_sites]"
puts "OVERLAP_COUNT=[llength $overlap]"
puts "OVERLAP=[join $overlap { }]"
close_design
