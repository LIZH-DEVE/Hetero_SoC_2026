open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/engineering_evidence/shadow_mirror_20260402_095104/raw_impl_reports/udp_gateway_shadow_mirror_wrapper_postroute_physopt.dcp}

set crypto_cells [list \
  [get_cells -quiet udp_gateway_shadow_mirror_i/crypto_accel_axi_0] \
]

set data_cells [list \
  [get_cells -quiet udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/i_hybrid_dma] \
  [get_cells -quiet udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_shadow_acl_filter] \
  [get_cells -quiet udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_classifier] \
  [get_cells -quiet udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/gen_shadow_ctrl_csr.u_shadow_ctrl_csr] \
]

set ctrl_cells [list \
  [get_cells -quiet udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/gen_shadow_inject_only.u_shadow_inject] \
  [get_cells -quiet udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader] \
]

foreach pair {
  {crypto $crypto_cells}
  {data   $data_cells}
  {ctrl   $ctrl_cells}
} {
  lassign $pair name cells_var
  set cells [concat {*}[set $cells_var]]
  puts "=== GROUP $name ==="
  puts "CELL_COUNT=[llength $cells]"
  puts "CELLS_BEGIN"
  puts [join [lsort $cells] "\n"]
  puts "CELLS_END"
  if {[catch {report_utilization -cells $cells -return_string} util]} {
    puts "UTILIZATION_ERROR=$util"
  } else {
    puts $util
  }
}

close_design
exit
