set project_path "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr"
set bd_path "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.srcs/sources_1/bd/udp_gateway_shadow_mirror/udp_gateway_shadow_mirror.bd"
set component_path "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.gen/sources_1/bd/mref/dma_gateway_hybrid_board_wrapper/component.xml"

open_project $project_path
set bd_file [get_files $bd_path]
open_bd_design $bd_file
validate_bd_design
save_bd_design
reset_target all $bd_file
generate_target all $bd_file

puts "==== COMPONENT_MTIME ===="
puts [file mtime $component_path]

foreach pin {dma_gateway_hybrid_0/m_axi_dma_wr dma_gateway_hybrid_0/m_axi_fetcher dma_gateway_hybrid_0/m_axi_s2mm processing_system7_0/S_AXI_HP0} {
  puts "==== $pin ===="
  catch {report_property [get_bd_intf_pins $pin]}
}

close_project
