open_project D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr
open_bd_design [get_files D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.srcs/sources_1/bd/udp_gateway_shadow_mirror/udp_gateway_shadow_mirror.bd]
foreach pin {dma_gateway_hybrid_0/m_axi_dma_wr dma_gateway_hybrid_0/m_axi_fetcher dma_gateway_hybrid_0/m_axi_s2mm processing_system7_0/S_AXI_HP0 axi_mem_intercon/M00_AXI axi_mem_intercon/S00_AXI axi_mem_intercon/S01_AXI axi_mem_intercon/S02_AXI} {
  puts "==== $pin ===="
  catch {report_property [get_bd_intf_pins $pin]}
}
close_project
