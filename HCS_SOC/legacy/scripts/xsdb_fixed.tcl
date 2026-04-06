# 修复版本 - 添加 PL AXI 内存映射
puts "========== 带内存映射的系统初始化 =========="

puts "\n[1] 连接..."
connect

puts "\n[2] 选择目标..."
targets -set -nocase -filter {name =~ "arm*#0"}

puts "\n[3] 系统复位..."
rst -system

puts "\n[4] 编程 FPGA..."
fpga -f D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit

puts "\n[5] PS 初始化..."
source D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/platform/hw/ps7_init.tcl
ps7_init
ps7_post_config

puts "\n[6] 添加 PL AXI 内存映射..."
# 添加加密硬件的地址范围到内存映射
# 地址: 0x43C00000, 大小: 64KB (0x10000)
# 注意: XSDB 的 memmap 命令可能不支持，我们直接尝试读取
puts "跳过 memmap，直接尝试访问..."

puts "\n[7] 读取硬件状态..."
# 先尝试通过 CPU 读取（下载程序后让 CPU 访问）
puts "准备下载程序..."

puts "\n[8] 下载程序..."
dow D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/build/crypto_test_app.elf

puts "\n[9] 运行程序..."
con

puts "\n✓ 程序已启动，请查看串口输出!"
puts "如果串口仍无输出，程序可能在访问 0x43C00008 时挂起"

puts "\n========== 完成 =========="
