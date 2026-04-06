set workspace_root {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC}
open_project [file join $workspace_root HCS_SOC.xpr]
set raw_bd [file join $workspace_root HCS_SOC.srcs sources_1 bd raw_copy_dma raw_copy_dma.bd]
open_bd_design $raw_bd
set cell [get_bd_cells dma_raw_copy_subsystem_0]
puts "BEFORE update_module_reference"
catch {report_property $cell}
set rc [catch {update_module_reference $cell} msg]
puts "UPDATE_RC=$rc"
puts "UPDATE_MSG=$msg"
validate_bd_design
save_bd_design
close_bd_design [current_bd_design]
set bd_file [get_files -all $raw_bd]
puts "BD_FILE=$bd_file"
generate_target all $bd_file
set exp_rc [catch {export_ip_user_files -of_objects $bd_file -sync -force -quiet} exp_msg]
puts "EXPORT_IP_USER_FILES_RC=$exp_rc"
puts "EXPORT_IP_USER_FILES_MSG=$exp_msg"
set xci [get_files -all [file normalize [file join $workspace_root HCS_SOC.srcs sources_1 bd raw_copy_dma ip raw_copy_dma_dma_raw_copy_subsystem_0_0 raw_copy_dma_dma_raw_copy_subsystem_0_0.xci]]]
puts "XCI=$xci"
puts "XCI_SYNTH_CP_MODE=[get_property SYNTH_CHECKPOINT_MODE $xci]"
set dcp [get_files -all [file normalize [file join $workspace_root HCS_SOC.gen sources_1 bd raw_copy_dma ip raw_copy_dma_dma_raw_copy_subsystem_0_0 raw_copy_dma_dma_raw_copy_subsystem_0_0.dcp]]]
puts "MODULE_REF_DCP=$dcp"
if {[llength $dcp]} {report_property $dcp}
close_project
