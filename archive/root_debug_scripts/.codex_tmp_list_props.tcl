open_project -quiet D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr
set xci [get_files -quiet D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.srcs/sources_1/bd/raw_copy_dma/ip/raw_copy_dma_dma_raw_copy_subsystem_0_0/raw_copy_dma_dma_raw_copy_subsystem_0_0.xci]
puts "=== SYNTH PROPS ==="
foreach p [lsort [list_property $xci]] {
  if {[string match *SYNTH* $p] || [string match *CHECKPOINT* $p] || [string match *REFRESH* $p]} { puts "$p = [get_property $p $xci]" }
}
close_project
