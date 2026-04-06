# 波特率精确修复: 75MHz UART_REF, 目标 115200 baud
# BRGR=93, BDIV=6 → 75,000,000 / (93×7) = 115,434 bps ✓
puts "===== 修复 UART1 波特率 (75MHz → 115200) ====="

stop
after 100

# 禁用 TX/RX (防止写寄存器时出错)
mwr 0xE0001000 0x00000028

# 写入正确的 BRGR 和 BDIV
mwr 0xE0001018 93   ;# BRGR: 75M / (93×7) = 115,434 bps
mwr 0xE000101C 6    ;# BDIV

# 重新使能
mwr 0xE0001000 0x00000114
after 20

puts "验证: BRGR=[mrd -value 0xE0001018], BDIV=[mrd -value 0xE000101C]"
puts [format "UART1_SR = 0x%08x" [mrd -value 0xE000102C]]

# 直写测试
puts "发送 '115200OK' 到 UART1..."
foreach b {0x31 0x31 0x35 0x32 0x30 0x30 0x4F 0x4B 0x0D 0x0A} {
    mwr 0xE0001030 $b
}
after 200

# 恢复 CPU
con
puts "===== 完成，观察 PuTTY ====="
