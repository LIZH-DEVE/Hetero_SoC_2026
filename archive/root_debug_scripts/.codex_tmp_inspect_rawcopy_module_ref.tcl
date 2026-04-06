set workspace_root {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC}
open_project [file join $workspace_root HCS_SOC.xpr]
set xci [get_files -all [file normalize [file join $workspace_root HCS_SOC.srcs sources_1 bd raw_copy_dma ip raw_copy_dma_dma_raw_copy_subsystem_0_0 raw_copy_dma_dma_raw_copy_subsystem_0_0.xci]]]
puts "=== XCI ==="
puts $xci
if {[llength $xci]} {
  report_property $xci
}
set dcp [get_files -all [file normalize [file join $workspace_root HCS_SOC.gen sources_1 bd raw_copy_dma ip raw_copy_dma_dma_raw_copy_subsystem_0_0 raw_copy_dma_dma_raw_copy_subsystem_0_0.dcp]]]
puts "=== DCP ==="
puts $dcp
if {[llength $dcp]} {
  report_property $dcp
}
open_bd_design [file join $workspace_root HCS_SOC.srcs sources_1 bd raw_copy_dma raw_copy_dma.bd]
set cell [get_bd_cells dma_raw_copy_subsystem_0]
puts "=== BD CELL ==="
report_property $cell
puts "=== CELL REF ==="
puts "TYPE=[get_property TYPE $cell] VLNV=[get_property VLNV $cell] REF_NAME=[get_property CONFIG.Component_Name $cell]"
close_bd_design [current_bd_design]
close_project
