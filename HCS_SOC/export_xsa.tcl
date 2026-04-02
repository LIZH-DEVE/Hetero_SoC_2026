set workspace_root [file normalize [file dirname [info script]]]
set project_file [file join $workspace_root "HCS_SOC.xpr"]
set design1_bd [file join $workspace_root "HCS_SOC.srcs" "sources_1" "bd" "design_1" "design_1.bd"]
set out_xsa [file join $workspace_root "design_1_wrapper.xsa"]
set vendor_ps_config [file normalize [file join $workspace_root ".." ".." "AX7020_2023.1" "course_s2_vitis" "08_ps_uart" "Vivado" "auto_create_project" "ps_config.tcl"]]

if {![file exists $project_file]} {
    error "project file not found: $project_file"
}
if {![file exists $design1_bd]} {
    error "design_1.bd not found: $design1_bd"
}
if {![file exists $vendor_ps_config]} {
    error "vendor ps_config.tcl not found: $vendor_ps_config"
}

open_project -quiet $project_file

puts "Using BD: $design1_bd"
open_bd_design [get_files $design1_bd]
source $vendor_ps_config
if {![llength [info procs set_ps_config]]} {
    error "vendor ps_config.tcl did not define set_ps_config"
}
puts "Applying vendor PS preset from: $vendor_ps_config"
set_ps_config processing_system7_0
validate_bd_design
save_bd_design
close_bd_design [current_bd_design]

generate_target all [get_files $design1_bd]
make_wrapper -files [get_files $design1_bd] -top -force
update_compile_order -fileset sources_1
set_property top design_1_wrapper [current_fileset]
puts "Top set to: [get_property top [current_fileset]]"

reset_run synth_1
reset_run impl_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "synth_1 status: $synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "synth_1 failed: $synth_status"
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1 status: $impl_status"
if {![string match "*Complete*" $impl_status]} {
    error "impl_1 failed: $impl_status"
}

set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set bit_file [file join $impl_dir "design_1_wrapper.bit"]
if {![file exists $bit_file]} {
    error "bitstream not found after impl: $bit_file"
}
puts "design_1 bitstream: $bit_file"

write_hw_platform -fixed -include_bit -force -file $out_xsa
puts "Exported XSA: $out_xsa"

close_project
