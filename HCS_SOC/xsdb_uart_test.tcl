# UART 硬件直写测试 - 完全绕过 CPU 程序
# 在 XSDB 中直接操作 UART 寄存器

puts "========== UART 硬件诊断 =========="

# 停止 CPU
stop
after 200

# ---- 测试 UART0 (0xE0000000) ----
puts "\n[1] 测试 UART0 (0xE0000000)..."
puts "    检查 UART0 状态寄存器..."
set sr0 [mrd -value 0xE000002C]
puts [format "    UART0 SR = 0x%08x" $sr0]
# Bit4=TXFULL, Bit3=TXEMPTY
set txfull0 [expr {($sr0 >> 4) & 1}]
set txempty0 [expr {($sr0 >> 3) & 1}]
puts [format "    TX FULL=%d, TX EMPTY=%d" $txfull0 $txempty0]

if {$txfull0 == 0} {
    puts "    直接写 'H' 到 UART0 FIFO..."
    mwr 0xE0000030 0x48
    mwr 0xE0000030 0x49
    mwr 0xE0000030 0x0D
    mwr 0xE0000030 0x0A
    puts "    → 如果串口显示 'HI'，说明你的串口接的是 UART0"
} else {
    puts "    UART0 TX FIFO 满，跳过"
}

after 100

# ---- 测试 UART1 (0xE0001000) ----
puts "\n[2] 测试 UART1 (0xE0001000)..."
puts "    检查 UART1 状态寄存器..."
set sr1 [mrd -value 0xE000102C]
puts [format "    UART1 SR = 0x%08x" $sr1]
set txfull1 [expr {($sr1 >> 4) & 1}]
set txempty1 [expr {($sr1 >> 3) & 1}]
puts [format "    TX FULL=%d, TX EMPTY=%d" $txfull1 $txempty1]

if {$txfull1 == 0} {
    puts "    直接写 'W' 到 UART1 FIFO..."
    mwr 0xE0001030 0x57
    mwr 0xE0001030 0x4F
    mwr 0xE0001030 0x0D
    mwr 0xE0001030 0x0A
    puts "    → 如果串口显示 'WO'，说明你的串口接的是 UART1"
} else {
    puts "    UART1 TX FIFO 满，跳过"
}

puts "\n[3] 结论："
puts "    观察 PuTTY 串口，看出现 'HI' 还是 'WO'"
puts "    如果都没有，说明串口线或波特率���问题"
puts "\n========== 诊断完成 =========="
