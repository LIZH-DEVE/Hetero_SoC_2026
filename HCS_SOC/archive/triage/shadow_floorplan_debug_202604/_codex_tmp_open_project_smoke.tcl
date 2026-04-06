set project_file [file normalize {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr}]
puts "OPEN_PROJECT_SMOKE path=$project_file exists=[file exists $project_file]"
open_project -quiet $project_file
puts "OPEN_PROJECT_SMOKE_OK"
close_project
exit
