open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp}
proc slice_used_avail {pblock_name} {
  set util [report_utilization -pblocks [get_pblocks $pblock_name] -return_string]
  if {[regexp {\| Slice\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|} $util -> used avail]} {
    return [list $used $avail]
  }
  return [list NA NA]
}
proc test_geom {name live_rects data_rects} {
  open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp}
  set live [get_pblocks live_crypto_region]
  set data [get_pblocks shadow_data_region]
  resize_pblock $live -remove [get_sites -of_objects $live]
  resize_pblock $data -remove [get_sites -of_objects $data]
  resize_pblock $live -add $live_rects
  resize_pblock $data -add $data_rects
  set drc [report_drc -checks {FLBO-1 UTLZ-3} -return_string]
  set flbo [expr {[regexp {FLBO-1} $drc] ? 1 : 0}]
  set utlz [expr {[regexp {UTLZ-3} $drc] ? 1 : 0}]
  lassign [slice_used_avail live_crypto_region] lu la
  lassign [slice_used_avail shadow_data_region] du da
  puts "$name,flbo=$flbo,utlz=$utlz,live=$lu/$la,data=$du/$da"
  puts "$name LIVE=[get_property GRID_RANGES $live]"
  puts "$name DATA=[get_property GRID_RANGES $data]"
  close_design
}
set data_common {SLICE_X0Y0:SLICE_X113Y49 RAMB36_X3Y0:RAMB36_X5Y11}
# candidate A: move live pocket left, move data center right
set live_a {SLICE_X24Y99:SLICE_X113Y149 SLICE_X26Y50:SLICE_X39Y98}
set data_a {SLICE_X0Y0:SLICE_X113Y49 SLICE_X68Y50:SLICE_X95Y98 RAMB36_X3Y0:RAMB36_X5Y11}
# candidate B: live pocket left-middle wider, data center right-middle
set live_b {SLICE_X24Y99:SLICE_X113Y149 SLICE_X40Y50:SLICE_X53Y98}
set data_b {SLICE_X0Y0:SLICE_X113Y49 SLICE_X68Y50:SLICE_X95Y98 RAMB36_X3Y0:RAMB36_X5Y11}
# candidate C: live pocket left, data center center-right narrower to avoid shadow_ctrl edge
set live_c {SLICE_X24Y99:SLICE_X113Y149 SLICE_X26Y50:SLICE_X39Y98}
set data_c {SLICE_X0Y0:SLICE_X113Y49 SLICE_X68Y50:SLICE_X89Y98 RAMB36_X3Y0:RAMB36_X5Y11}
puts "name,flbo,utlz,live,data"
test_geom candA $live_a $data_a
test_geom candB $live_b $data_b
test_geom candC $live_c $data_c
exit
