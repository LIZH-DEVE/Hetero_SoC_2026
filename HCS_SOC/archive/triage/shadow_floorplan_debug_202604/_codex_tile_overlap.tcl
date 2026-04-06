open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp}
proc report_overlap {label} {
  set liveTiles [lsort -unique [get_tiles -quiet -of_objects [get_pblocks live_crypto_region]]]
  set dataTiles [lsort -unique [get_tiles -quiet -of_objects [get_pblocks shadow_data_region]]]
  set liveSites [lsort -unique [get_sites -quiet -of_objects [get_pblocks live_crypto_region]]]
  set dataSites [lsort -unique [get_sites -quiet -of_objects [get_pblocks shadow_data_region]]]
  set tileOverlap [lsort -unique [lsearch -all -inline -exact $liveTiles $dataTiles]]
  set siteOverlap [lsort -unique [lsearch -all -inline -exact $liveSites $dataSites]]
  puts "$label tiles=[llength $tileOverlap] sites=[llength $siteOverlap]"
  if {[llength $tileOverlap] > 0} {
    puts "$label first_tiles=[lrange $tileOverlap 0 20]"
  }
}
report_overlap current
resize_pblock [get_pblocks live_crypto_region] -remove [get_sites -of_objects [get_pblocks live_crypto_region]]
resize_pblock [get_pblocks shadow_data_region] -remove [get_sites -of_objects [get_pblocks shadow_data_region]]
resize_pblock [get_pblocks live_crypto_region] -add {SLICE_X0Y100:SLICE_X113Y149 SLICE_X80Y51:SLICE_X95Y98}
resize_pblock [get_pblocks shadow_data_region] -add {SLICE_X0Y0:SLICE_X113Y49 SLICE_X26Y50:SLICE_X79Y98 RAMB36_X3Y0:RAMB36_X5Y11}
report_overlap ygap
resize_pblock [get_pblocks live_crypto_region] -remove [get_sites -of_objects [get_pblocks live_crypto_region]]
resize_pblock [get_pblocks shadow_data_region] -remove [get_sites -of_objects [get_pblocks shadow_data_region]]
resize_pblock [get_pblocks live_crypto_region] -add {SLICE_X0Y100:SLICE_X113Y149 SLICE_X80Y51:SLICE_X95Y98}
resize_pblock [get_pblocks shadow_data_region] -add {SLICE_X0Y0:SLICE_X79Y49 SLICE_X26Y50:SLICE_X79Y98 RAMB36_X3Y0:RAMB36_X5Y11}
report_overlap xcut_bottom
exit
