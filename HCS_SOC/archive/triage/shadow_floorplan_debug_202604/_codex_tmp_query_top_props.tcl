open_project -quiet {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr}
puts "FILESET_TOP=[get_property top [current_fileset]]"
puts "FILESET_TOP_AUTO_SET=[get_property top_auto_set [current_fileset]]"
puts "SYNTH_TOP=[get_property top [get_runs synth_1]]"
puts "SYNTH_TOP_AUTO_SET=[get_property top_auto_set [get_runs synth_1]]"
puts "IMPL_TOP=[get_property top [get_runs impl_1]]"
puts "IMPL_TOP_AUTO_SET=[get_property top_auto_set [get_runs impl_1]]"
close_project
