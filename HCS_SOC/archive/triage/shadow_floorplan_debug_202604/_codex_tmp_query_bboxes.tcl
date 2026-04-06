open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper_postroute_physopt.dcp}
proc bbox {pattern label} {
  set cells [get_cells -quiet -hierarchical -filter "NAME =~ $pattern"]
  set xs {}
  set ys {}
  foreach c $cells {
    set s [get_property SITE $c]
    if {[regexp {SLICE_X([0-9]+)Y([0-9]+)} $s -> x y]} {
      lappend xs $x
      lappend ys $y
    }
  }
  if {[llength $xs] > 0} {
    puts "$label=SLICE_X[lindex [lsort -integer $xs] 0]Y[lindex [lsort -integer $ys] 0]:SLICE_X[lindex [lsort -integer $xs] end]Y[lindex [lsort -integer $ys] end]"
  } else {
    puts "$label=NONE"
  }
}
bbox {udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/i_hybrid_dma/*} HYBRID_DMA_BBOX
bbox {udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/gen_shadow_inject_only.u_shadow_inject/*} SHADOW_INJECT_BBOX
bbox {udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/gen_shadow_ctrl_csr.u_shadow_ctrl_csr/*} SHADOW_CSR_BBOX
bbox {udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader/*} DNA_BBOX
bbox {udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_shadow_acl_filter/*} ACL_BBOX
bbox {udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_classifier/*} CLASS_BBOX
close_design
exit
