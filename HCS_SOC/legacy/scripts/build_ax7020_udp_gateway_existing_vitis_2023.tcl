set workspace "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/vitis_2023_udp_gateway_ws_2"

puts "Workspace: $workspace"
setws $workspace
sysproj build -name ax7020_udp_gateway_app_system
puts "BUILD_DONE"
exit
