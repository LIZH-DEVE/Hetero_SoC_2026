# 简化调试脚本 - 一步一步执行
# 按 Ctrl+C 停止当前脚本后运行此脚本

puts "===== [1] 连接 ====="
connect
targets -set -nocase -filter {name =~ "arm*#0"}

puts "===== [2] 停止 CPU ====="
stop
after 500

puts "===== [3] 检查当前状态 ====="
puts "PC: [mrd 0xF8000100]"

puts "===== [4] 手动初始化 UART1 (不重置系统) ====="
set UART1_BASE 0xE0001000

# 使能 UART 时钟
puts "使能 UART 时钟..."
mwr 0xF8000008 0x0000DF0D
mwr 0xF8000154 0x00003F03
mwr 0xF8000004 0x0000767B
after 100

# 复位并配置 UART
puts "配置 UART..."
mwr $UART1_BASE 0x00000000
after 50
mwr [expr $UART1_BASE + 0x18] 0x0000007B
mwr [expr $UART1_BASE + 0x34] 0x00000006
mwr [expr $UART1_BASE + 0x04] 0x00000020
mwr $UART1_BASE 0x00000014
after 100

puts "UART_CR: [mrd $UART1_BASE]"
puts "UART_SR: [mrd [expr $UART1_BASE + 0x2C]]"

puts "===== [5] 发送测试字符 ====="
mwr [expr $UART1_BASE + 0x30] 0x00000058
after 10
mwr [expr $UART1_BASE + 0x30] 0x00000059
after 10
mwr [expr $UART1_BASE + 0x30] 0x0000005A
after 10
mwr [expr $UART1_BASE + 0x30] 0x0000000D
after 10
mwr [expr $UART1_BASE + 0x30] 0x0000000A

puts "已发送 XYZ\\r\\n，请检查 PuTTY"
puts "UART_SR: [mrd [expr $UART1_BASE + 0x2C]]"

puts "===== 完成 ====="
