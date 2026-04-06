open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_postroute_physopt.dcp}
proc max_site {pattern} {
  set sites [lsort [get_sites -quiet $pattern]]
  if {[llength $sites] == 0} {
    puts "$pattern=<none>"
  } else {
    puts "$pattern first=[lindex $sites 0] last=[lindex $sites end] count=[llength $sites]"
  }
}
max_site SLICE_X*
max_site DSP48_X*
max_site RAMB18_X*
max_site RAMB36_X*
close_design
exit
