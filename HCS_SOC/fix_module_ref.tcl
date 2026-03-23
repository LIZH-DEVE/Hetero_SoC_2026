# 剔除崩溃的旧路径文件依赖
remove_files [get_files -quiet "*_corrupted_*"]

# 添加已经被抢救存活的正统 RTL 包装文件
add_files -norecurse -scan_for_includes "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/core/crypto_axi/crypto_accel_axi.v"
add_files -norecurse -scan_for_includes "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/rtl/core/crypto_axi/crypto_accel_axi_slave_lite_v1_0_S00_AXI.v"

# 强制 Vivado 重新排布编译顺序
update_compile_order -fileset sources_1

# 告诉 Block Design 里的这个模块，它的老家已经搬到了本地的 rtl 文件夹下，并立刻刷新其引脚映射
open_bd_design [get_files design_1.bd]
update_module_reference design_1_crypto_accel_axi_0_1

# 验证 Block Design 无误
assign_bd_address
validate_bd_design
save_bd_design

# 强制清空之前烂掉的综合中间产物，并全量生成真正的 0xACE 位流
puts "===== 正在清空旧缓存并启动综合 ====="
reset_run synth_1
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "===== 【破茧重生】纯天然且映射完善的新版位流生成完毕！请继续去 Vitis 刷新硬件 ===== "
