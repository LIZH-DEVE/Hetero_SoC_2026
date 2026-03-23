# UART 和加密模块诊断脚本 v2
# 修复 mrd 返回值解析问题

puts "===== [1] 连接目标 ====="
connect
targets -set -nocase -filter {name =~ "arm*#0"}

# 辅助函数：从 mrd 返回值中提取数值
proc get_mrd_value {addr} {
    set result [mrd $addr]
    # mrd 返回格式: "地址:   数值"
    set parts [split $result ":"]
    if {[llength $parts] >= 2} {
        set val_str [string trim [lindex $parts 1]]
        return [expr 0x$val_str]
    }
    return 0
}

puts "===== [2] 读取 UART1 寄存器状态 ====="

# UART1 基地址
set UART1_BASE 0xE0001000

puts "UART_CR (Control):       0x[format %08X [get_mrd_value $UART1_BASE]]"
puts "UART_MR (Mode):          0x[format %08X [get_mrd_value [expr $UART1_BASE + 0x04]]]"
puts "UART_IMR (Interrupt Mask): 0x[format %08X [get_mrd_value [expr $UART1_BASE + 0x10]]]"
puts "UART_BAUDGEN:            0x[format %08X [get_mrd_value [expr $UART1_BASE + 0x18]]]"
puts "UART_BAUD_DIV:           0x[format %08X [get_mrd_value [expr $UART1_BASE + 0x34]]]"

set sr [get_mrd_value [expr $UART1_BASE + 0x2C]]
puts "UART_SR (Channel Status): 0x[format %08X $sr]"
puts "  - TXEMPTY: [expr ($sr >> 3) & 1]"
puts "  - TXFULL:  [expr ($sr >> 4) & 1]"
puts "  - RXEMPTY: [expr ($sr >> 1) & 1]"

puts "\n===== [3] 读取加密模块状态 ====="
set CRYPTO_BASE 0x43C00000
set status [get_mrd_value $CRYPTO_BASE]
puts "CRYPTO_STATUS: 0x[format %08X $status]"

# 检查硬件指纹
set fingerprint [expr ($status >> 20) & 0xFFF]
puts "Hardware Fingerprint: 0x[format %03X $fingerprint]"
if {$fingerprint == 0xACE} {
    puts "  [OK] Hardware Version V2.1 detected!"
} else {
    puts "  [ERR] Hardware fingerprint mismatch! Expected 0xACE"
}

puts "\n===== [4] 检查 UART 时钟控制 ====="
set clk_ctrl [get_mrd_value 0xF8000154]
puts "UART_CLK_CTRL: 0x[format %08X $clk_ctrl]"
puts "  - UART0_CLKACT: [expr $clk_ctrl & 1]"
puts "  - UART1_CLKACT: [expr ($clk_ctrl >> 1) & 1]"
puts "  - DIVISOR: [expr ($clk_ctrl >> 8) & 0x3F]"

puts "\n===== [5] 检查 AMBA 时钟 ====="
set amba [get_mrd_value 0xF800012C]
puts "AMBA_CLK_CTRL: 0x[format %08X $amba]"
puts "  - UART0_CPU_1XCLKACT: [expr ($amba >> 20) & 1]"
puts "  - UART1_CPU_1XCLKACT: [expr ($amba >> 21) & 1]"

puts "\n===== [6] 检查 MIO 配置 (UART1: MIO48/TX, MIO49/RX) ====="
puts "MIO_PIN_48 (TX): 0x[format %08X [get_mrd_value [expr 0xF8000700 + 48*4]]]"
puts "MIO_PIN_49 (RX): 0x[format %08X [get_mrd_value [expr 0xF8000700 + 49*4]]]"

puts "\n===== [7] 尝试手动初始化 UART1 ====="
# 使能 UART 时钟
mwr 0xF8000154 0x00000303
after 100

# 复位 UART
mwr $UART1_BASE 0x00000000
after 100

# 设置波特率 115200 @ 100MHz
# BAUDGEN = 0x7B (123), DIV = 6
mwr [expr $UART1_BASE + 0x18] 0x0000007B
mwr [expr $UART1_BASE + 0x34] 0x00000006

# 设置模式: 8N1, 无奇偶校验
mwr [expr $UART1_BASE + 0x04] 0x00000020

# 使能 TX/RX
mwr $UART1_BASE 0x00000014

after 100
puts "UART_SR after init: 0x[format %08X [get_mrd_value [expr $UART1_BASE + 0x2C]]]"

puts "\n===== [8] 尝试发送测试字符 ====="
mwr [expr $UART1_BASE + 0x30] 0x00000041
after 10
mwr [expr $UART1_BASE + 0x30] 0x00000042
after 10
mwr [expr $UART1_BASE + 0x30] 0x00000043
after 10
mwr [expr $UART1_BASE + 0x30] 0x0000000A

puts "UART_SR after TX: 0x[format %08X [get_mrd_value [expr $UART1_BASE + 0x2C]]]"

puts "\n===== 诊断完成 ====="
