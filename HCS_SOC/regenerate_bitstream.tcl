# Vivado 自动化脚本 - 重新生成位流文件
# 日期: 2026-03-15
# 目的: 清除缓存后重新生成包含硬件指纹 0xACE 的位流文件

# 打开项目
open_project d:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/hcs_soc/HCS_SOC.xpr

# 禁用增量编译
set_property incremental_checkpoint.none 1 [current_run synth_1]
set_property incremental_checkpoint.none 1 [current_run impl_1]

# 重置运行
reset_run synth_1
reset_run impl_1

# 启动综合
puts "=========================================="
puts "  [1/3] 开始综合..."
puts "=========================================="
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# 检查综合状态
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: 综合失败！"
    exit 1
}
puts "SUCCESS: 综合完成！"

# 启动实现
puts "=========================================="
puts "  [2/3] 开始实现..."
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
puts "  [3/3] 生成位流文件..."
puts "=========================================="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# 检查位流生成状态
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: 位流生成失败！"
    exit 1
}
puts "SUCCESS: 位流生成完成！"

# 导出硬件（包含位流）
puts "=========================================="
puts "  导出硬件平台..."
puts "=========================================="
write_hw_platform -fixed -include_bit -force -file d:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/hcs_soc/design_1_wrapper.xsa

puts ""
puts "=========================================="
puts "  所有步骤完成！"
puts "=========================================="
puts ""
puts "位流文件位置:"
puts "  d:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/hcs_soc/HCS_SOC.runs/impl_1/design_1_wrapper.bit"
puts ""
puts "硬件平台文件:"
puts "  d:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/hcs_soc/design_1_wrapper.xsa"
puts ""
puts "请在 Vitis 中更新硬件平台并重新编译程序！"
puts ""

# 关闭项目
close_project

exit 0
