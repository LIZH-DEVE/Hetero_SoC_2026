set workspace_root {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC}
set project_file [file join $workspace_root HCS_SOC.xpr]
set source_bd [file join $workspace_root HCS_SOC.srcs sources_1 bd dma_gateway_hybrid dma_gateway_hybrid.bd]
set raw_bd_name udp_gateway_shadow_mirror
set raw_bd [file normalize [file join $workspace_root HCS_SOC.srcs sources_1 bd $raw_bd_name ${raw_bd_name}.bd]]
open_project -quiet $project_file
set_property source_mgmt_mode All [current_project]
if {[llength [get_files -quiet $raw_bd]] != 0} {
  catch {remove_files [get_files -quiet $raw_bd]}
}
foreach stale_raw_fileset [get_filesets -quiet "${raw_bd_name}_*"] {
  catch {delete_fileset $stale_raw_fileset}
}
foreach stale_raw_run [get_runs -quiet "${raw_bd_name}_*"] {
  catch {delete_run $stale_raw_run}
}
save_project_as $project_file -force
open_bd_design $source_bd
puts OK_OPEN_SOURCE_BD
close_project
