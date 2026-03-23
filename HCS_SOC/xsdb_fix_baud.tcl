# ============================================================
# 波特率修复脚本
# 问题: UART_CLK_CTRL DIVISOR=20 → 80MHz → 184502bps (乱码)
# 修复: DIVISOR=32 → 50MHz → 115207bps ≈ 115200 ✓
# ============================================================
puts "========== 波特率修复 =========="

stop
after 100

# ---- 1. 修正 UART_CLK_CTRL ----
puts "\n[1] 修正 UART_CLK_CTRL 分频比: DIVISOR 20→32"
puts "    50MHz = 1600MHz(IO_PLL) ÷ 32"
mwr -force 0xF8000008 0x0000DF0D   ;# 解锁 SLCR

# UART_CLK_CTRL = 0x00002003:
#   bits[1:0]  = 11  → CLKACT (UART0+UART1 都开)
#   bits[5:4]  = 00  → SRCSEL = IO_PLL
#   bits[13:8] = 0x20=32 → DIVISOR=32 → 1600/32=50MHz
mwr -force 0xF8000154 0x00002003

mwr -force 0xF8000004 0x0000767B   ;# 重新锁定 SLCR
after 20

puts "    UART_CLK_CTRL = [format 0x%08x [mrd -value 0xF8000154]]"
puts "    → 实际 UART_REF_CLK = 1600MHz÷32 = 50MHz"

# ---- 2. 确认 UART1 BRGR/BDIV ----
puts "\n[2] 确认 UART1 波特率寄存器 (目标 115200 @ 50MHz)"
set brg [mrd -value 0xE0001018]
set bdi [mrd -value 0xE000101C]
puts [format "    BRGR = %d" $brg]
puts [format "    BDIV = %d" $bdi]
if {$brg > 0 && $bdi > 0} {
    set actual_baud [expr {int(50000000.0 / ($brg * ($bdi + 1)))}]
    puts [format "    → 实际波特率 ≈ %d bps" $actual_baud]
}

# 如果 BRGR 不对，强制写入
if {$brg != 62 || $bdi != 6} {
    puts "    BRGR/BDIV 不正确，强制写入 62/6..."
    mwr 0xE0001018 62
    mwr 0xE000101C 6
}

# 确保 TX 使能
mwr 0xE0001000 0x00000114
after 10

# ---- 3. 发送测试字符 ----
puts "\n[3] 发送测试字符串 '115200OK\\r\\n' 到 UART1 FIFO..."
set test_str {49 31 31 35 32 30 30 4F 4B 0D 0A}
# '1','1','5','2','0','0','O','K',CR,LF
foreach b {0x31 0x31 0x35 0x32 0x30 0x30 0x4F 0x4B 0x0D 0x0A} {
    mwr 0xE0001030 $b
}
puts "    → PuTTY 应出现: 115200OK"
after 500

# ---- 4. 同时发测试到 UART0 ----
puts "\n[4] 发送 'UART0\\r\\n' 到 UART0..."
foreach b {0x55 0x41 0x52 0x54 0x30 0x0D 0x0A} {
    mwr 0xE0000030 $b
}
puts "    → 若另一个串口出现 'UART0'，说明两个口都接了"

# ---- 5. 检查 SR ----
puts "\n[5] 状态确认:"
set sr1 [mrd -value 0xE000102C]
puts [format "    UART1_SR = 0x%08x" $sr1]
puts [format "    TXEMPTY = %d" [expr {($sr1 >> 3) & 1}]]

puts "\n[6] 恢复 CPU 运行..."
con

puts "✓ 波特率已修复，程序继续运行"
puts "  PuTTY: 115200 baud，应出现 'ABC' 和测试banner"
puts "========== 完成 =========="
