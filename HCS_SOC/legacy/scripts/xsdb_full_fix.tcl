# 完整修复脚本 v3 - 手动初始化 UART 和验证 PL
# 问题：UART_CR=0，PL 地址被 XSDB 阻止

puts "===== [1] 连接并停止 CPU ====="
connect
targets -set -nocase -filter {name =~ "arm*#0"}
stop
after 500

puts "===== [2] 系统重置 ====="
rst -system
after 2000

puts "===== [3] 烧录位流 ====="
fpga -f "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit"
after 2000

puts "===== [4] PS 初始化 ====="
targets -set -nocase -filter {name =~ "arm*#0"}
stop
source "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/platform/hw/ps7_init.tcl"
ps7_init
ps7_post_config
after 500

puts "===== [5] 手动初始化 UART1 ====="
# UART1 基地址
set UART1_BASE 0xE0001000

# 1. 使能 UART 时钟 (应该已由 ps7_init 完成，再次确认)
mwr 0xF8000154 0x00003F03
after 100

# 2. 复位 UART
mwr $UART1_BASE 0x00000000
after 100

# 3. 设置波特率 115200 @ 100MHz
# BAUDGEN = 0x7B (123), BAUD_DIV = 6
# 实际波特率 = 100MHz / (123 * (6+1)) = 115942 ≈ 115200
mwr [expr $UART1_BASE + 0x18] 0x0000007B
mwr [expr $UART1_BASE + 0x34] 0x00000006

# 4. 设置模式: 8N1, 无奇偶校验, 正常模式
mwr [expr $UART1_BASE + 0x04] 0x00000020

# 5. 使能 TX 和 RX
mwr $UART1_BASE 0x00000014

after 100
puts "UART_CR: [mrd $UART1_BASE]"
puts "UART_SR: [mrd [expr $UART1_BASE + 0x2C]]"

puts "===== [6] 测试 UART 输出 ====="
# 发送测试字符 "ABC\n"
mwr [expr $UART1_BASE + 0x30] 0x00000041
after 10
mwr [expr $UART1_BASE + 0x30] 0x00000042
after 10
mwr [expr $UART1_BASE + 0x30] 0x00000043
after 10
mwr [expr $UART1_BASE + 0x30] 0x0000000A
after 100

puts "UART_SR after TX: [mrd [expr $UART1_BASE + 0x2C]]"
puts "请检查 PuTTY 是否收到 'ABC'"

puts "===== [7] 下载 ELF ====="
dow "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/build/crypto_test_app.elf"
after 500

puts "===== [8] 运行程序 ====="
con

puts "===== 完成! 请检查 PuTTY ====="
