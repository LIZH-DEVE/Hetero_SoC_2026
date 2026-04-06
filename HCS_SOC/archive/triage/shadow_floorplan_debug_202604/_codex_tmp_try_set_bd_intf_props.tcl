open_project D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr
open_bd_design [get_files D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.srcs/sources_1/bd/udp_gateway_shadow_mirror/udp_gateway_shadow_mirror.bd]
foreach spec {
  {dma_gateway_hybrid_0/m_axi_dma_wr CONFIG.MAX_BURST_LENGTH 16}
  {dma_gateway_hybrid_0/m_axi_dma_wr CONFIG.NUM_WRITE_OUTSTANDING 1}
  {dma_gateway_hybrid_0/m_axi_dma_wr CONFIG.SUPPORTS_NARROW_BURST 0}
  {dma_gateway_hybrid_0/m_axi_fetcher CONFIG.MAX_BURST_LENGTH 16}
  {dma_gateway_hybrid_0/m_axi_fetcher CONFIG.NUM_READ_OUTSTANDING 1}
  {dma_gateway_hybrid_0/m_axi_fetcher CONFIG.SUPPORTS_NARROW_BURST 0}
  {dma_gateway_hybrid_0/m_axi_s2mm CONFIG.MAX_BURST_LENGTH 16}
  {dma_gateway_hybrid_0/m_axi_s2mm CONFIG.NUM_READ_OUTSTANDING 1}
  {dma_gateway_hybrid_0/m_axi_s2mm CONFIG.NUM_WRITE_OUTSTANDING 1}
  {dma_gateway_hybrid_0/m_axi_s2mm CONFIG.SUPPORTS_NARROW_BURST 0}
} {
  lassign $spec pin prop value
  puts "TRY $pin $prop=$value"
  if {[catch {set_property $prop $value [get_bd_intf_pins $pin]} err]} {
    puts "FAIL $err"
  } else {
    puts "OK [get_property $prop [get_bd_intf_pins $pin]]"
  }
}
close_project
