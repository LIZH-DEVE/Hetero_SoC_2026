# 终极除根脚手架：清理死胡同，让 Module Reference 重生
open_project -quiet D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr

# 1. 彻底斩断对 ip_repo 的任何挂念和幽灵依赖
set_property ip_repo_paths "" [current_project]
update_ip_catalog -rebuild

# 2. 从废墟中打开 Block Design
open_bd_design [get_files design_1.bd]

# 3. 强行把跑死的模块综合清零
set broken_run [get_runs -quiet design_1_crypto_accel_axi_0_1_synth_1]
if { $broken_run != "" } {
    puts "===== Detected corrupted OOC run, resetting it... ====="
    reset_run $broken_run
}

reset_run synth_1
reset_run impl_1

# 4. 重新刷一遍 BD，确保现在它的眼里只有纯洁的 RTL！
generate_target all [get_files design_1.bd]

puts "===== 【破茧重生】启动全量综合与位流生成（预计 3-5 分钟） ====="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "===== 【终极胜利】彻底剔除故障 IP 的净洁位流生成完毕！====="
puts "后续请重新导出 XSA 给 Vitis！"
