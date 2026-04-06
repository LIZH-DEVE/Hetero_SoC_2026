set project_file {D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr}
open_project -quiet $project_file
foreach f [lsort [get_files -all -quiet *udp_gateway_shadow_mirror*]] {
  puts $f
}
close_project
