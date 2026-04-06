open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_postroute_physopt.dcp}
set objs [list \
  udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/gen_shadow_ctrl_csr.u_shadow_ctrl_csr/s_axil_rdata[0]_i_7 \
  udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/gen_shadow_ctrl_csr.u_shadow_ctrl_csr/s_axil_rdata[1]_i_7 \
  udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/gen_shadow_ctrl_csr.u_shadow_ctrl_csr/s_axil_rdata[2]_i_7 \
  udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/gen_shadow_ctrl_csr.u_shadow_ctrl_csr/s_axil_rdata[3]_i_7 \
  udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/gen_shadow_ctrl_csr.u_shadow_ctrl_csr/s_axil_rdata[4]_i_7 \
  udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader/s_axil_rdata_reg[0]_i_2 \
  udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader/s_axil_rdata_reg[1]_i_2 \
  udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader/s_axil_rdata_reg[2]_i_2 \
  udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader/s_axil_rdata_reg[3]_i_2 \
  udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader/s_axil_rdata_reg[4]_i_2 \
]
foreach name $objs {
  set c [get_cells -quiet $name]
  if {[llength $c] == 0} { puts "MISS::$name"; continue }
  puts "CELL::$name SITE=[get_property SITE $c] PBLOCKS=[join [get_pblocks -of_objects $c] ,]"
}
set crypto_cells [get_cells -quiet -hierarchical -filter {NAME =~ udp_gateway_shadow_mirror_i/crypto_accel_axi_0/inst/*}]
puts "CRYPTO_COUNT=[llength $crypto_cells]"
set xs {}
set ys {}
foreach c $crypto_cells {
  set s [get_property SITE $c]
  if {$s eq ""} { continue }
  if {[regexp {SLICE_X([0-9]+)Y([0-9]+)} $s -> x y]} {
    lappend xs $x
    lappend ys $y
  }
}
if {[llength $xs] > 0} {
  puts "CRYPTO_BBOX=SLICE_X[lindex [lsort -integer $xs] 0]Y[lindex [lsort -integer $ys] 0]:SLICE_X[lindex [lsort -integer $xs] end]Y[lindex [lsort -integer $ys] end]"
}
close_design
exit
