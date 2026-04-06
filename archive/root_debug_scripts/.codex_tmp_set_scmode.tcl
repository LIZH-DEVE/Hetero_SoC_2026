open_project -quiet D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr
set xci [get_files -quiet D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.srcs/sources_1/bd/raw_copy_dma/ip/raw_copy_dma_dma_raw_copy_subsystem_0_0/raw_copy_dma_dma_raw_copy_subsystem_0_0.xci]
puts "before=[get_property SYNTH_CHECKPOINT_MODE $xci]"
set_property SYNTH_CHECKPOINT_MODE None $xci
puts "after=[get_property SYNTH_CHECKPOINT_MODE $xci]"
close_project
