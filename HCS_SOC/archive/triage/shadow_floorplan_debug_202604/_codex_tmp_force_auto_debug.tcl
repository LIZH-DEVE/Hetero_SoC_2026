proc force_auto_compile_order {} {
    set project_obj [lindex [get_projects -quiet] 0]
    puts "PROJECT_OBJ=<$project_obj> COUNT=[llength [get_projects -quiet]]"
    current_project $project_obj
    set_property source_mgmt_mode All $project_obj
    update_compile_order -fileset sources_1
}
set project_file [file normalize {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr}]
open_project -quiet $project_file
puts "AFTER_OPEN projects=[get_projects -quiet] current=[current_project -quiet]"
force_auto_compile_order
puts "FORCE_AUTO_OK"
close_project
exit
