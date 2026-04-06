open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp}
proc apply_geom {live_top pocket_start data_bottom data_center_top} {
    set live [get_pblocks live_crypto_region]
    set data [get_pblocks shadow_data_region]
    resize_pblock $live -remove [get_sites -of_objects $live]
    resize_pblock $data -remove [get_sites -of_objects $data]
    resize_pblock $live -add [format {SLICE_X0Y%d:SLICE_X113Y149 SLICE_X80Y%d:SLICE_X95Y98} $live_top $pocket_start]
    resize_pblock $data -add [format {SLICE_X0Y0:SLICE_X113Y%d SLICE_X26Y50:SLICE_X79Y%d RAMB36_X3Y0:RAMB36_X5Y11} $data_bottom $data_center_top]
}
proc slice_sites {pblock_name} {
    set util [report_utilization -pblocks [get_pblocks $pblock_name] -return_string]
    if {[regexp {\| Slice\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|} $util -> used avail]} {
        return [list $used $avail]
    }
    return [list NA NA]
}
puts "live_top,pocket_start,data_bottom,data_center_top,flbo,utlz,live_used,live_avail,data_used,data_avail"
foreach pocket_start {51 52 53} {
  foreach data_bottom {49 48 47} {
    foreach data_center_top {98 97 96} {
      open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_routed.dcp}
      apply_geom 100 $pocket_start $data_bottom $data_center_top
      set drc [report_drc -checks {FLBO-1 UTLZ-3} -return_string]
      set flbo [expr {[regexp {FLBO-1} $drc] ? 1 : 0}]
      set utlz [expr {[regexp {UTLZ-3} $drc] ? 1 : 0}]
      lassign [slice_sites live_crypto_region] live_used live_avail
      lassign [slice_sites shadow_data_region] data_used data_avail
      puts "100,$pocket_start,$data_bottom,$data_center_top,$flbo,$utlz,$live_used,$live_avail,$data_used,$data_avail"
      close_design
    }
  }
}
exit
