# ============================================================
# UART 时钟/MIO 完整诊断 + 修复脚本
# 目标: 找出 UART SR=0x00000000 的根本原因并修复
# 运行方法: 在已完成 fpga + ps7_init 之后运行本脚本
# ============================================================
puts "========== UART 时钟与 MIO 深度诊断 =========="

# 先停止 CPU
stop
after 200

# -------- 1. 读取 APER_CLK_CTRL (UART 外设时钟使能) --------
puts "\n[1] APER_CLK_CTRL (0xF800012C) - 外设时钟使能寄存器"
puts "    Bit 20 = UART0_CPU_1XCLKACT, Bit 21 = UART1_CPU_1XCLKACT"
set aper [mrd -value 0xF800012C]
puts [format "    当前值 = 0x%08x" $aper]
set uart0_clk [expr {($aper >> 20) & 1}]
set uart1_clk [expr {($aper >> 21) & 1}]
puts [format "    UART0 时钟: %s" [expr {$uart0_clk ? "✓ 已使能" : "✗ 未使能"}]]
puts [format "    UART1 时钟: %s" [expr {$uart1_clk ? "✓ 已使能" : "✗ 未使能"}]]

# -------- 2. 读取 UART_CLK_CTRL (UART 分频时钟) --------
puts "\n[2] UART_CLK_CTRL (0xF8000154) - UART 时钟分频寄存器"
puts "    Bit 0 = CLKACT0(UART0), Bit 1 = CLKACT1(UART1)"
set uclk [mrd -value 0xF8000154]
puts [format "    当前值 = 0x%08x" $uclk]
set u0act [expr {($uclk >> 0) & 1}]
set u1act [expr {($uclk >> 1) & 1}]
puts [format "    UART0 分频时钟: %s" [expr {$u0act ? "✓ 活跃" : "✗ 停止"}]]
puts [format "    UART1 分频时钟: %s" [expr {$u1act ? "✓ 活跃" : "✗ 停止"}]]

# -------- 3. 读取 MIO 引脚配置 (UART1 = MIO48/49) --------
puts "\n[3] MIO ��脚配置 (UART1 默认使用 MIO48=TX, MIO49=RX)"
set mio48 [mrd -value 0xF80007C0]
set mio49 [mrd -value 0xF80007C4]
puts [format "    MIO_PIN_48 (0xF80007C0) = 0x%08x" $mio48]
puts [format "    MIO_PIN_49 (0xF80007C4) = 0x%08x" $mio49]
# L3_SEL[7:5] = 011 → UART; SPEED[8]=1; IO_TYPE[11:9]=001 (LVCMOS33)
set mio48_l3 [expr {($mio48 >> 5) & 0x7}]
set mio49_l3 [expr {($mio49 >> 5) & 0x7}]
puts [format "    MIO48 L3_SEL = %d %s" $mio48_l3 [expr {$mio48_l3 == 7 ? "(UART)" : "(非UART! 期望7)"}]]
puts [format "    MIO49 L3_SEL = %d %s" $mio49_l3 [expr {$mio49_l3 == 7 ? "(UART)" : "(非UART! 期望7)"}]]

puts "\n[3b] 同时检查 UART0 MIO 引脚 (通常 MIO14=TX, MIO15=RX)"
set mio14 [mrd -value 0xF8000738]
set mio15 [mrd -value 0xF800073C]
puts [format "    MIO_PIN_14 (0xF8000738) = 0x%08x" $mio14]
puts [format "    MIO_PIN_15 (0xF800073C) = 0x%08x" $mio15]
set mio14_l3 [expr {($mio14 >> 5) & 0x7}]
set mio15_l3 [expr {($mio15 >> 5) & 0x7}]
puts [format "    MIO14 L3_SEL = %d %s" $mio14_l3 [expr {$mio14_l3 == 7 ? "(UART)" : "(非UART)"}]]
puts [format "    MIO15 L3_SEL = %d %s" $mio15_l3 [expr {$mio15_l3 == 7 ? "(UART)" : "(非UART)"}]]

# -------- 4. 读取 UART1 模式寄存器和波特率 --------
puts "\n[4] UART1 配置寄存器详情"
set u1mr  [mrd -value 0xE0001004]
set u1brg [mrd -value 0xE0001018]
set u1bdi [mrd -value 0xE000101C]
set u1cr  [mrd -value 0xE0001000]
puts [format "    UART1_CR  (0xE0001000) = 0x%08x" $u1cr]
puts [format "    UART1_MR  (0xE0001004) = 0x%08x" $u1mr]
puts [format "    UART1_BRGR(0xE0001018) = 0x%08x" $u1brg]
puts [format "    UART1_BDIV(0xE000101C) = 0x%08x" $u1bdi]
set u1tx_en [expr {($u1cr >> 4) & 1}]
set u1rx_en [expr {($u1cr >> 2) & 1}]
set u1txdis [expr {($u1cr >> 5) & 1}]
puts [format "    TX_EN=%d TX_DIS=%d RX_EN=%d" $u1tx_en $u1txdis $u1rx_en]
# 计算波特率: Baud = RefClk / (BRGR * (BDIV+1))
if {$u1brg > 0} {
    set baud_ref [expr {int(50000000.0 / ($u1brg * ($u1bdi + 1)))}]
    puts [format "    估算波特率 ≈ %d bps (基于50MHz参考时钟)" $baud_ref]
}

# -------- 5. 同时检查 UART0 --------
puts "\n[5] UART0 配置寄存器"
set u0cr  [mrd -value 0xE0000000]
set u0brg [mrd -value 0xE0000018]
set u0bdi [mrd -value 0xE000001C]
puts [format "    UART0_CR  (0xE0000000) = 0x%08x" $u0cr]
puts [format "    UART0_BRGR(0xE0000018) = 0x%08x" $u0brg]
puts [format "    UART0_BDIV(0xE000001C) = 0x%08x" $u0bdi]

# -------- 6. 关键诊断 + 自动修复 --------
puts "\n[6] ===== 问题诊断 ====="

set need_fix 0

if {$uart1_clk == 0} {
    puts "  !! UART1 APER 时钟未使能 → 这是根本原因!"
    set need_fix 1
}
if {$u1act == 0} {
    puts "  !! UART1 分频时钟未使能"
    set need_fix 1
}
if {$u1brg == 0} {
    puts "  !! UART1_BRGR = 0 → 波特率除数为零，UART 无法工作!"
    set need_fix 1
}
if {$u1tx_en == 0 || $u1txdis == 1} {
    puts "  !! UART1 TX 未使能 (TX_EN=0 或 TX_DIS=1)"
    set need_fix 1
}

if {$need_fix == 0} {
    puts "  时钟/配置看起来正常，问题可能在 MIO 引脚或物理连线"
}

puts "\n[7] ===== 强制手动初始化 UART1 ====="
puts "    解锁 SLCR..."
mwr -force 0xF8000008 0x0000DF0D

puts "    1) 使能 UART1 APER 时钟 (APER_CLK_CTRL bit21=1, bit20=1)..."
set aper_new [mrd -value 0xF800012C]
set aper_new [expr {$aper_new | 0x00300000}]
mwr -force 0xF800012C $aper_new
after 10

puts "    2) 使能 UART_CLK_CTRL: 两路时钟都打开..."
set uclk_val [mrd -value 0xF8000154]
set uclk_val [expr {$uclk_val | 0x00000003}]
mwr -force 0xF8000154 $uclk_val
after 10

puts "    3) 配置 MIO48(TX)/MIO49(RX) 为 UART1..."
# MIO: SPEED=1(fast), IO_TYPE=001(LVCMOS33), PULLUP=1, L3_SEL=111(UART), DisableRcvr=0
# 值 = 0x000016E0: speed=1, IO_TYPE=001, pullup=1, L3=111, L2=00, L1=0, L0=0
mwr -force 0xF80007C0 0x000016E0
mwr -force 0xF80007C4 0x000016E1
after 10

puts "    4) 重新锁定 SLCR..."
mwr -force 0xF8000004 0x0000767B

puts "    5) 复位 UART1 控制器..."
# CR: RX_DIS=1, TX_DIS=1 (先禁用)
mwr 0xE0001000 0x00000028
after 5
# CR: RXRST=1, TXRST=1 (软复位 FIFO)
mwr 0xE0001000 0x00000003
after 5

puts "    6) 配置 UART1 波特率 = 115200 @ 100MHz IO PLL..."
# 100MHz / (62 * (6+1)) = 100MHz / 434 ≈ 230400?
# 正确: 对于 UART_REF_CLK=50MHz: BRGR=62, BDIV=6 → 50MHz/(62*7)=115207bps
# 对于 UART_REF_CLK=100MHz: BRGR=62, BDIV=13 → 100MHz/(62*14)=115207bps
# ps7_init 中时钟分频: UART_CLK_CTRL的DIVISOR决定实际频率
# 先用最保守值: 读取实际分频后决定
# 暂用 BRGR=62, BDIV=6 (对应50MHz参考时钟)
mwr 0xE0001018 62
mwr 0xE000101C 6
after 5

puts "    7) 配置 UART1 模式: 8N1..."
# MR: CHRL=00(8bit), PAR=100(无校验), NBSTOP=00(1stop), CHMODE=00(Normal)
mwr 0xE0001004 0x00000020
after 5

puts "    8) 使能 TX 和 RX..."
# CR: TX_EN=1, RX_EN=1
mwr 0xE0001000 0x00000114
after 10

puts "\n[8] 验证修复后的寄存器状态:"
set u1sr_new  [mrd -value 0xE000102C]
set u1cr_new  [mrd -value 0xE0001000]
set u1brg_new [mrd -value 0xE0001018]
puts [format "    UART1_SR  = 0x%08x" $u1sr_new]
puts [format "    UART1_CR  = 0x%08x" $u1cr_new]
puts [format "    UART1_BRGR= 0x%08x" $u1brg_new]
set u1txfull  [expr {($u1sr_new >> 4) & 1}]
set u1txempty [expr {($u1sr_new >> 3) & 1}]
puts [format "    TXFULL=%d TXEMPTY=%d" $u1txfull $u1txempty]

if {$u1sr_new != 0} {
    puts "    ★ SR 非零！UART 时钟已使能，硬件响应正常"
    puts "\n[9] 发送测试字符到 UART1..."
    mwr 0xE0001030 0x48 ;# 'H'
    mwr 0xE0001030 0x45 ;# 'E'
    mwr 0xE0001030 0x4C ;# 'L'
    mwr 0xE0001030 0x4C ;# 'L'
    mwr 0xE0001030 0x4F ;# 'O'
    mwr 0xE0001030 0x0D ;# CR
    mwr 0xE0001030 0x0A ;# LF
    puts "    已写入 'HELLO\\r\\n' → 观察 PuTTY UART1"
    after 500

    puts "\n[10] 同样测试 UART0..."
    set u0sr_new [mrd -value 0xE000002C]
    puts [format "    UART0_SR = 0x%08x" $u0sr_new]
    if {$u0sr_new != 0} {
        mwr 0xE0000030 0x48 ;# 'H'
        mwr 0xE0000030 0x49 ;# 'I'
        mwr 0xE0000030 0x0D
        mwr 0xE0000030 0x0A
        puts "    已写入 'HI\\r\\n' → 观察 PuTTY UART0"
    }
} else {
    puts "    ✗ SR 仍为 0！问题更深层。可能原因:"
    puts "      - ps7_init.tcl 没有配置 UART_CLK_CTRL (0xF8000154)"
    puts "      - MIO 引脚未分配给 UART"
    puts "      - Vivado 块设计中 UART 未连接到 MIO"
    puts "      → 请检查 Vivado PS 配置: MIO Configuration → I/O Peripherals → UART"
}

puts "\n========== 诊断完成 =========="
