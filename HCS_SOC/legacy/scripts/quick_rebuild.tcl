# Vivado 快速重新编译脚本
# 只运行实现和位流生成，跳过综合

# 打开项目
open_project d:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/hcs_soc/HCS_SOC.xpr

# 更新 IP
update_ip_catalog -rebuild

# 重置实现运行
reset_run impl_1

# 启动实现
puts "=========================================="
puts "  [1/2] 开始实现..."
puts "=========================================="
launch_runs impl_1 -jobs 4
wait_on_run impl_1

# 检查实现状态
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: 实现失败！"
    exit 1
}
puts "SUCCESS: 实现完成！"

# 生成位流
puts "=========================================="
puts "  [2/2] 生成位流文件..."
puts "=========================================="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# 检查位流生成状态
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: 位流生成失败！"
    exit 1
}
puts "SUCCESS: 位流生成完成！"

# 导出硬件
puts "=========================================="
puts "  导出硬件平台..."
puts "=========================================="
write_hw_platform -fixed -include_bit -force -file d:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/hcs_soc/design_1_wrapper.xsa

puts ""
puts "=========================================="
puts "  编译完成！"
puts "=========================================="

# 关闭项目
close_project

exit 0
