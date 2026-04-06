open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp}
set vios [get_drc_violations -quiet -filter {NAME =~ "FLBO-1*"}]
puts "COUNT=[llength $vios]"
foreach v $vios {
  puts "VIOLATION=$v"
  puts [report_property -return_string $v]
}
exit
