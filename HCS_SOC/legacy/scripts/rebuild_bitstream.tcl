# 强制更新 crypto_accel_axi IP 并重新生成位流
# 在 Vivado Tcl Console 中执行

puts "===== [1] 强制刷新 IP 仓库 ====="
set ip_repo_path "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/ip_repo"
set_property ip_repo_paths $ip_repo_path [current_project]
update_ip_catalog -rebuild

puts "===== [2] 升级 crypto_accel_axi IP ====="
upgrade_ip [get_ips crypto_accel_axi_0] -vlnv xilinx.com:user:crypto_accel_axi:1.0

puts "===== [3] 重新生成 IP 输出产物 ====="
generate_target all [get_ips crypto_accel_axi_0]

puts "===== [4] 清理旧综合结果 ====="
reset_run synth_1
reset_run impl_1

puts "===== [5] 启动位流生成 (后台运行) ====="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "===== 位流生成完成! ====="
puts "新位流位置: [get_property DIRECTORY [get_runs impl_1]]/design_1_wrapper.bit"
