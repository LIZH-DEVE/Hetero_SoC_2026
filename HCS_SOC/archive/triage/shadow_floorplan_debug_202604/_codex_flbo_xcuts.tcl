open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp}
proc apply_geom {live_top pocket_start data_bottom_x data_bottom_y data_center_x data_center_top} {
    set live [get_pblocks live_crypto_region]
    set data [get_pblocks shadow_data_region]
    resize_pblock $live -remove [get_sites -of_objects $live]
    resize_pblock $data -remove [get_sites -of_objects $data]
    resize_pblock $live -add [format {SLICE_X0Y%d:SLICE_X113Y149 SLICE_X80Y%d:SLICE_X95Y98} $live_top $pocket_start]
    resize_pblock $data -add [format {SLICE_X0Y0:SLICE_X%dY%d SLICE_X26Y50:SLICE_X%dY%d RAMB36_X3Y0:RAMB36_X5Y11} $data_bottom_x $data_bottom_y $data_center_x $data_center_top]
}
puts "name,flbo,utlz"
foreach candidate {
  {src_patch 100 51 113 49 79 98}
  {xcut_bottom 100 51 79 49 79 98}
  {xcut_bottom_ygap 100 52 79 48 79 97}
  {xcut_bottom_more 100 51 67 49 79 98}
  {xcut_both 100 51 79 49 67 98}
  {xcut_both_gap 100 52 79 48 67 97}
} {
  lassign $candidate name live_top pocket_start data_bottom_x data_bottom_y data_center_x data_center_top
  open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp}
  apply_geom $live_top $pocket_start $data_bottom_x $data_bottom_y $data_center_x $data_center_top
  set drc [report_drc -checks {FLBO-1 UTLZ-3} -return_string]
  set flbo [expr {[regexp {FLBO-1} $drc] ? 1 : 0}]
  set utlz [expr {[regexp {UTLZ-3} $drc] ? 1 : 0}]
  puts "$name,$flbo,$utlz"
  close_design
}
exit
