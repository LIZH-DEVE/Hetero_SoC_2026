open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_postroute_physopt.dcp}
proc q {name} {
  set s [get_sites -quiet $name]
  if {[llength $s] == 0} {puts "$name=MISS"} else {puts "$name=OK"}
}
foreach n {
  SLICE_X22Y100 SLICE_X23Y100 SLICE_X24Y100 SLICE_X25Y100 SLICE_X26Y100 SLICE_X27Y100
  SLICE_X66Y100 SLICE_X67Y100 SLICE_X68Y100 SLICE_X79Y100 SLICE_X80Y100 SLICE_X81Y100
  SLICE_X92Y50 SLICE_X95Y50 SLICE_X96Y50 SLICE_X97Y50 SLICE_X103Y65 SLICE_X106Y68
} { q $n }
close_design
exit
