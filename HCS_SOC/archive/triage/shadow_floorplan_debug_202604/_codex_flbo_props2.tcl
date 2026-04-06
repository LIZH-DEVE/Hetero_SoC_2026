open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp}
report_drc -checks {FLBO-1}
set vios [get_drc_violations -quiet -filter {RULE_NAME == FLBO-1}]
puts "COUNT=[llength $vios]"
foreach v $vios {
  puts "VIOLATION=$v"
  puts [report_property -return_string $v]
}
exit
