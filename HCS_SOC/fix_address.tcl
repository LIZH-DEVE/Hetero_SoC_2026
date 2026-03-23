# 终极修复：精准修正 AXI 地址映射
# 在 Vivado Tcl Console 中执行

# 1. 打开设计
open_bd_design [get_files design_1.bd]

# 2. 根据诊断出的精准路径修正地址
# 路径是从诊断脚本结果中提取的：/processing_system7_0/Data/SEG_crypto_accel_axi_0_reg0
set_property offset 0x43C00000 [get_bd_addr_segs /processing_system7_0/Data/SEG_crypto_accel_axi_0_reg0]
set_property range 64K [get_bd_addr_segs /processing_system7_0/Data/SEG_crypto_accel_axi_0_reg0]

# 3. 验证并保存
assign_bd_address
validate_bd_design
save_bd_design

# 4. 重新启动 Implementation 生成位流
# 地址映射的改变会导致网表变化，必须重跑
puts "===== 正在启动包含正确地址 (0x43C00000) 的全量编译 ====="
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "===== 【终极胜利】地址修正并编译完毕！ ====="
puts "请现在运行极简 XSDB 脚本：source D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/xsdb_minimal.tcl"
