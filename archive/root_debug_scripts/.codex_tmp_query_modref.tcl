open_project -quiet D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr
set xci [get_files -quiet D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.srcs/sources_1/bd/raw_copy_dma/ip/raw_copy_dma_dma_raw_copy_subsystem_0_0/raw_copy_dma_dma_raw_copy_subsystem_0_0.xci]
set run [get_runs -quiet raw_copy_dma_dma_raw_copy_subsystem_0_0_synth_1]
puts "=== XCI ==="
report_property $xci
puts "=== RUN ==="
report_property $run
puts "=== FILES FOR MODULE REF ==="
foreach f [get_files -all *raw_copy_dma_dma_raw_copy_subsystem_0_0*] { puts "$f :: [get_property FILE_TYPE $f] :: used_in_synth=[get_property USED_IN_SYNTHESIS $f] used_in_impl=[get_property USED_IN_IMPLEMENTATION $f]" }
puts "=== BD CELL ==="
open_bd_design [get_files D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.srcs/sources_1/bd/raw_copy_dma/raw_copy_dma.bd]
set cell [get_bd_cells dma_raw_copy_subsystem_0]
report_property $cell
close_project
