set workspace_root {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC}
set project_file [file join $workspace_root HCS_SOC.xpr]
open_project -quiet $project_file
set_property source_mgmt_mode All [current_project]
set src [get_filesets sources_1]
set_property top_auto_set 0 $src
set_property top udp_gateway_shadow_mirror_wrapper $src
update_compile_order -fileset sources_1
launch_runs synth_1 -scripts_only
close_project
