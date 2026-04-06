open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_postroute_physopt.dcp}
proc max_coord {pattern label} {
  set maxx -1
  set maxy -1
  foreach site [get_sites -quiet $pattern] {
    if {[regexp {X([0-9]+)Y([0-9]+)$} $site -> x y]} {
      if {$x > $maxx} {set maxx $x}
      if {$y > $maxy} {set maxy $y}
    }
  }
  puts "$label maxX=$maxx maxY=$maxy"
}
max_coord SLICE_X* SLICE
max_coord DSP48_X* DSP48
max_coord RAMB18_X* RAMB18
max_coord RAMB36_X* RAMB36
close_design
exit
