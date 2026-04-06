open_project D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr
open_bd_design [get_files D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.srcs/sources_1/bd/system/system.bd]
set ip_cell [get_bd_cells /dma_subsystem_v2_wra_0]
if {[llength $ip_cell] == 0} { set ip_cell [get_bd_cells dma_subsystem_v2_wra_0] }
puts "Found cell: $ip_cell"
set_property -dict [list CONFIG.CRYPTO_NUM_INSTANCES {4}] $ip_cell
save_bd_design
generate_target all [get_files D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.srcs/sources_1/bd/system/system.bd]
update_compile_order -fileset sources_1
close_project
exit
