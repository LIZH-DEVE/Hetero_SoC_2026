set workspace_root {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC}
open_project [file join $workspace_root HCS_SOC.xpr]
set xci [get_files -all [file normalize [file join $workspace_root HCS_SOC.srcs sources_1 bd raw_copy_dma ip raw_copy_dma_dma_raw_copy_subsystem_0_0 raw_copy_dma_dma_raw_copy_subsystem_0_0.xci]]]
puts "SYNTH_CHECKPOINT_MODE current=[get_property SYNTH_CHECKPOINT_MODE $xci]"
if {[catch {set_property SYNTH_CHECKPOINT_MODE None $xci} err]} {
  puts "SET_FAIL=$err"
} else {
  puts "SET_OK new=[get_property SYNTH_CHECKPOINT_MODE $xci]"
}
close_project
