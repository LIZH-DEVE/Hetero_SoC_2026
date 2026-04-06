open_checkpoint {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/doc/reports/engineering_evidence/shadow_mirror_20260402_095104/raw_impl_reports/udp_gateway_shadow_mirror_wrapper_postroute_physopt.dcp}
read_xdc {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/constraints/shadow_mirror_phasec_constraints.xdc}

puts "=== PBLOCKS ==="
foreach pb [lsort [get_pblocks -quiet *]] {
  puts "PBLOCK=$pb"
  puts "CELL_COUNT_DIRECT=[llength [get_cells -quiet -of_objects [get_pblocks $pb]]]"
  puts [report_property -return_string [get_pblocks $pb]]
  puts "DIRECT_CELLS_BEGIN"
  puts [join [lsort [get_cells -quiet -of_objects [get_pblocks $pb]]] "\n"]
  puts "DIRECT_CELLS_END"
  if {[catch {report_utilization -pblocks [get_pblocks $pb] -return_string} util]} {
    puts "UTILIZATION_ERROR=$util"
  } else {
    puts "UTILIZATION_BEGIN"
    puts $util
    puts "UTILIZATION_END"
  }
}

puts "=== TARGET_CELL_MATCHES ==="
foreach pattern {
  {udp_gateway_shadow_mirror_i/crypto_accel_axi_0/inst}
  {udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/i_hybrid_dma}
  {udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_shadow_acl_filter}
  {udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_classifier}
  {udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/gen_shadow_ctrl_csr.u_shadow_ctrl_csr}
  {udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/gen_shadow_inject_only.u_shadow_inject}
  {udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader}
} {
  puts "PATTERN=$pattern"
  puts [join [lsort [get_cells -hierarchical -quiet $pattern]] "\n"]
}

puts "=== DRC_SELECTED ==="
if {[catch {report_drc -checks {FLBO-1 FLBP-1 UTLZ-3} -return_string} drc]} {
  puts "DRC_ERROR=$drc"
} else {
  puts $drc
}

close_design
exit
