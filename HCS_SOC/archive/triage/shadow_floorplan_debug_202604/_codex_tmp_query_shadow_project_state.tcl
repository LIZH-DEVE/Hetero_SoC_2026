set project_file "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr"
open_project -quiet $project_file
set proj [current_project]
set src [get_filesets sources_1]
puts "SOURCE_MGMT_MODE=[get_property source_mgmt_mode $proj]"
puts "SRC_TOP=[get_property top $src]"
puts "SRC_TOP_AUTO_SET=[get_property top_auto_set $src]"
set wrapper_file [lindex [get_files -quiet */udp_gateway_shadow_mirror_wrapper.v] 0]
puts "WRAPPER_FILE=$wrapper_file"
if {$wrapper_file ne ""} {
    foreach prop {IS_ENABLED USED_IN_SYNTHESIS USED_IN_IMPLEMENTATION USED_IN_SIMULATION FILE_TYPE} {
        if {[catch {puts "$prop=[get_property $prop $wrapper_file]"}]} {
            puts "$prop=<unsupported>"
        }
    }
}
close_project
exit
