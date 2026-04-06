set workspace_root {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC}
open_project [file join $workspace_root HCS_SOC.xpr]
foreach rel {"HCS_SOC.srcs/sources_1/bd/raw_copy_dma/ip/raw_copy_dma_processing_system7_0_0/raw_copy_dma_processing_system7_0_0.xci" "HCS_SOC.gen/sources_1/bd/raw_copy_dma/ip/raw_copy_dma_processing_system7_0_0/raw_copy_dma_processing_system7_0_0.dcp" "HCS_SOC.srcs/sources_1/bd/raw_copy_dma/ip/raw_copy_dma_dma_raw_copy_subsystem_0_0/raw_copy_dma_dma_raw_copy_subsystem_0_0.xci" "HCS_SOC.gen/sources_1/bd/raw_copy_dma/ip/raw_copy_dma_dma_raw_copy_subsystem_0_0/raw_copy_dma_dma_raw_copy_subsystem_0_0.dcp"} {
  set abs [file normalize [file join $workspace_root $rel]]
  puts "=== $abs ==="
  set f [get_files -all $abs]
  puts "GET_FILES=$f"
  if {[llength $f]} {report_property $f}
}
close_project
