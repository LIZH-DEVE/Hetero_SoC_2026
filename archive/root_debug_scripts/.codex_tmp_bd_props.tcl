open_project -quiet D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr
open_bd_design [get_files D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.srcs/sources_1/bd/raw_copy_dma/raw_copy_dma.bd]
set cell [get_bd_cells dma_raw_copy_subsystem_0]
foreach p [lsort [list_property $cell]] { if {[string match *SYNTH* $p] || [string match *CHECKPOINT* $p] || [string match *REFRESH* $p] || [string match *GEN* $p]} { puts "$p = [get_property $p $cell]" } }
close_project
