set project_file "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr"
open_project -quiet $project_file
puts "TOP_BEFORE=[get_property top [current_fileset]]"
puts "TOPAUTO_BEFORE=[get_property top_auto_set [current_fileset]]"
reset_run synth_1
launch_runs synth_1 -scripts_only
set synth_dir [get_property DIRECTORY [get_runs synth_1]]
puts "SYNTH_DIR=$synth_dir"
set tcls [glob -nocomplain [file join $synth_dir *.tcl]]
puts "SYNTH_TCLS=$tcls"
close_project
