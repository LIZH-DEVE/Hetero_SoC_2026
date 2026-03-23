# ALINX XC7Z020 完整初始化脚本
# 从头开始：重置 -> 烧录位流 -> PS初始化 -> UART配置

puts "===== [1] 断开并重新连接 ====="
disconnect
after 500
connect
after 1000

puts "===== [2] 选择目标并停止 ====="
targets -set -nocase -filter {name =~ "arm*#0"}
stop
after 500

puts "===== [3] 系统重置 ====="
rst -system
after 3000

puts "===== [4] 烧录位流 ====="
fpga -f "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit"
after 3000

puts "===== [5] 执行 PS 初始化 ====="
targets -set -nocase -filter {name =~ "arm*#0"}
stop
after 500

# 加载 ps7_init
source "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/platform/hw/ps7_init.tcl"

puts "执行 ps7_init..."
ps7_init
after 1000

puts "执行 ps7_post_config..."
ps7_post_config
after 500

puts "===== [6] 验证时钟配置 ====="
puts "UART_CLK_CTRL: [mrd 0xF8000154]"
puts "AMBA_CLK: [mrd 0xF800012C]"

puts "===== [7] 配置 UART1 ====="
set UART1_BASE 0xE0001000

# 解锁 SLCR
mwr 0xF8000008 0x0000DF0D

# 使能 UART1 时钟
mwr 0xF8000154 0x00003F03

# 锁定 SLCR
mwr 0xF8000004 0x0000767B
after 100

# 配置 UART1
mwr $UART1_BASE 0x00000000
after 50
mwr [expr $UART1_BASE + 0x18] 0x0000007B
mwr [expr $UART1_BASE + 0x34] 0x00000006
mwr [expr $UART1_BASE + 0x04] 0x00000020
mwr $UART1_BASE 0x00000014
after 100

puts "UART_CR: [mrd $UART1_BASE]"
puts "UART_SR: [mrd [expr $UART1_BASE + 0x2C]]"

puts "===== [8] 发送测试字符 ====="
mwr [expr $UART1_BASE + 0x30] 0x00000048
mwr [expr $UART1_BASE + 0x30] 0x00000069
mwr [expr $UART1_BASE + 0x30] 0x0000000D
mwr [expr $UART1_BASE + 0x30] 0x0000000A

puts "已发送 'Hi\\r\\n'，请检查 PuTTY"

puts "===== [9] 下载并运行程序 ====="
dow "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/build/crypto_test_app.elf"
after 500
con

puts "===== 完成 ====="
