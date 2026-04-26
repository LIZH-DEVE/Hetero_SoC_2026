connect
puts "targets=[targets]"
catch {targets -set -filter {name =~ "*xc7z020*"}}
fpga -file {D:/JSA/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/udp_gateway_shadow_mirror_wrapper.bit}
puts "program_done=1"
