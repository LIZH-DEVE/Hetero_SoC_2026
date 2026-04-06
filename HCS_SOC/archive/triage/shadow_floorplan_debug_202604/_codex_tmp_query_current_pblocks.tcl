open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_postroute_physopt.dcp}
puts "TOP=[get_property TOP [current_design]]"
puts "PBLOCKS=[join [lsort [get_pblocks]] {,}]"
foreach p [lsort [get_pblocks]] {
  puts "PBLOCK::$p"
  puts [report_property -return_string $p]
}
close_design
exit
