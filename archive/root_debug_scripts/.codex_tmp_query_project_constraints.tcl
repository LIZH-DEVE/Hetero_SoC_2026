open_project {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr}
puts "=== FILESETS ==="
foreach fs [get_filesets] {puts "$fs type=[get_property FILESET_TYPE $fs]"}
puts "=== CONSTRS_1 FILES ==="
puts [join [get_files -quiet -of_objects [get_filesets constrs_1]] "`n"]
puts "=== SYNTH CONSTRSET ==="
puts [get_property constrset [get_runs synth_1]]
puts "=== IMPL CONSTRSET ==="
puts [get_property constrset [get_runs impl_1]]
puts "=== CURRENT PROJECT MODE ==="
puts [get_property source_mgmt_mode [current_project]]
close_project
exit
