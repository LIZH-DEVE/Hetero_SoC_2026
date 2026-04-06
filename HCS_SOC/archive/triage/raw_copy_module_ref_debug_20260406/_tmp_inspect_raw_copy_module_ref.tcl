set workspace_root [file normalize {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC}]
open_project [file join $workspace_root HCS_SOC.xpr]
set xci [get_files -quiet [file join $workspace_root HCS_SOC.srcs sources_1 bd raw_copy_dma ip raw_copy_dma_dma_raw_copy_subsystem_0_0 raw_copy_dma_dma_raw_copy_subsystem_0_0.xci]]
puts "XCI_COUNT=[llength $xci]"
if {[llength $xci]} {
  puts "XCI_USED_IN=[get_property used_in $xci]"
  puts "XCI_FILE_TYPE=[get_property file_type $xci]"
  puts "XCI_IS_ENABLED=[get_property is_enabled $xci]"
  puts "XCI_IP_OUTPUT_DIR=[get_property ip_output_dir $xci]"
}
set synth_v [get_files -quiet [file join $workspace_root HCS_SOC.gen sources_1 bd raw_copy_dma ip raw_copy_dma_dma_raw_copy_subsystem_0_0 synth raw_copy_dma_dma_raw_copy_subsystem_0_0.v]]
puts "SYNTH_V_COUNT=[llength $synth_v]"
if {[llength $synth_v]} {
  puts "SYNTH_V_USED_IN=[get_property used_in $synth_v]"
  puts "SYNTH_V_FILE_TYPE=[get_property file_type $synth_v]"
  puts "SYNTH_V_IS_ENABLED=[get_property is_enabled $synth_v]"
}
set wrap [get_files -quiet [file join $workspace_root HCS_SOC.gen sources_1 bd raw_copy_dma hdl raw_copy_dma_wrapper.v]]
puts "WRAP_COUNT=[llength $wrap]"
if {[llength $wrap]} {
  puts "WRAP_USED_IN=[get_property used_in $wrap]"
  puts "WRAP_FILE_TYPE=[get_property file_type $wrap]"
}
puts "TOP=[get_property top [current_fileset]]"
puts "COMPILE_ORDER_START"
foreach f [get_files -compile_order sources -used_in synthesis] {
  set n [file tail $f]
  if {[string match "*raw_copy_dma*" $n] || [string match "*dma_raw_copy*" $n]} {
    puts $f
  }
}
puts "COMPILE_ORDER_END"
close_project
