# ============================================================
# 完整修复流程: FPGA + PS初始化 + UART手动修复 + 下载运行
# 根本原因: ps7_init.tcl 未配置 UART 时钟 (APER_CLK_CTRL bit20/21 = 0)
# ============================================================
puts "========== 完整修复流程 (含 UART 时钟修复) =========="

# ---- [1] 连接与复位 ----
puts "\n[1] 连接与系统复位..."
catch {disconnect}
after 500
connect
targets -set -nocase -filter {name =~ "arm*#0"}
rst -system
after 1000

# ---- [2] 编程 FPGA ----
puts "\n[2] 编程 FPGA..."
fpga -f D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit

# ---- [3] PS 基础初始化 (不含 UART，由下面手动完成) ----
puts "\n[3] PS 基础初始化..."
source D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/platform/hw/ps7_init.tcl
ps7_init
ps7_post_config
after 200

# ---- [4] 手动修复 UART 时钟与 MIO ----
puts "\n[4] 手动使能 UART 时钟 (ps7_init.tcl 遗漏的部分)..."

# 解锁 SLCR
mwr -force 0xF8000008 0x0000DF0D

# 4a. 使能 APER_CLK_CTRL: bit20=UART0, bit21=UART1
puts "    使能 APER 外设时钟 (bit20=UART0, bit21=UART1)..."
set aper [mrd -value 0xF800012C]
puts [format "    APER_CLK_CTRL 修改前: 0x%08x" $aper]
# 同时设置 bit20 和 bit21
set aper [expr {$aper | 0x00300000}]
mwr -force 0xF800012C $aper
set aper_v [mrd -value 0xF800012C]
puts [format "    APER_CLK_CTRL 修改后: 0x%08x" $aper_v]

# 4b. 使能 UART_CLK_CTRL (0xF8000154): bit0=UART0, bit1=UART1
# 写入: CLKACT=11b, DIVISOR=20 (0x14), SRCSEL=00 (IO PLL)
# 对于 1000MHz IO_PLL, DIVISOR=20 → 50MHz UART参考时钟
puts "    配置 UART_CLK_CTRL → 50MHz (IO_PLL/20)..."
# bit[5:4]=SRCSEL=00(IOPLL), bits[13:8]=DIVISOR=20=0x14, bit[1:0]=CLKACT=11
mwr -force 0xF8000154 0x00001403

# 4c. 配置 MIO48(UART1 TX) 和 MIO49(UART1 RX)
puts "    配置 MIO48/49 → UART1..."
# MIO 寄存器格式 (0xF8000700 + pin*4):
#   [0]    = TRI_ENABLE (1=input only, 0=normal)
#   [2:1]  = L0_SEL
#   [3]    = L1_SEL
#   [5:4]  = L2_SEL
#   [7:5]  = L3_SEL: 111 = UART
#   [8]    = Speed: 1=fast
#   [11:9] = IO_Type: 001=LVCMOS33
#   [12]   = PULLUP: 1=enable
#   [13]   = DisableRcvr
# 值: L3=111(7), speed=1, IO_TYPE=001, PULLUP=1
# = (7<<5)|(1<<8)|(1<<9)|(1<<12) = 0xE0|0x100|0x200|0x1000 = 0x13E0
# 但标准 UART MIO 值: TX pin = 0x000016E0, RX pin = 0x000016E1 (TRI_ENABLE on RX)
# Ref: Zynq TRM MIO配置
mwr -force 0xF80007C0 0x000016E0  ;# MIO48: UART1_TX (L3_SEL=UART, fast, LVCMOS33, pullup)
mwr -force 0xF80007C4 0x000016E1  ;# MIO49: UART1_RX (同上 + TRI_ENABLE=1 for input)
puts [format "    MIO48 = 0x%08x" [mrd -value 0xF80007C0]]
puts [format "    MIO49 = 0x%08x" [mrd -value 0xF80007C4]]

# 4d. 同时配置 MIO14(UART0 TX), MIO15(UART0 RX) 以便都能测试
puts "    配置 MIO14/15 → UART0..."
mwr -force 0xF8000738 0x000016E0  ;# MIO14: UART0_TX
mwr -force 0xF800073C 0x000016E1  ;# MIO15: UART0_RX

# 重新锁定 SLCR
mwr -force 0xF8000004 0x0000767B
after 50

# ---- [5] 初始化 UART1 控制器 ----
puts "\n[5] 初始化 UART1 控制器 (115200 8N1)..."
# 软复位
mwr 0xE0001000 0x00000003  ;# RXRST + TXRST
after 20
# 配置模式: 8位, 无校验, 1停止位, Normal模式
mwr 0xE0001004 0x00000020  ;# MR: CHMODE=00, PAR=100(无校验), CHRL=00(8bit)
# 波特率: 50MHz / (62 * (6+1)) = 115207 bps ≈ 115200
mwr 0xE0001018 62           ;# BRGR
mwr 0xE000101C 6            ;# BDIV
# 使能 TX 和 RX
mwr 0xE0001000 0x00000114  ;# TX_EN + RX_EN + RXRST done
after 20

# ---- [6] 验证 UART1 状态 ----
puts "\n[6] 验证 UART1 状态寄存器..."
set sr [mrd -value 0xE000102C]
puts [format "    UART1_SR = 0x%08x" $sr]
set txfull  [expr {($sr >> 4) & 1}]
set txempty [expr {($sr >> 3) & 1}]
puts [format "    TXFULL=%d  TXEMPTY=%d" $txfull $txempty]

if {$sr != 0} {
    puts "    ★★★ UART SR 非零! 时钟修复成功! ★★★"
    puts "\n[7] 直写测试字符到 UART1 FIFO..."
    mwr 0xE0001030 0x4F  ;# 'O'
    mwr 0xE0001030 0x4B  ;# 'K'
    mwr 0xE0001030 0x21  ;# '!'
    mwr 0xE0001030 0x0D  ;# CR
    mwr 0xE0001030 0x0A  ;# LF
    puts "    已发送 'OK!' → 立刻看 PuTTY 是否出现 OK!"
    after 2000
} else {
    puts "    ✗✗✗ UART SR 仍为 0! UART 时钟未生效!"
    puts "    → 可能原因: Vivado 块设计中 UART MIO 引脚未分配"
    puts "    → 请在 Vivado Re-customize IP → PS → MIO Configuration"
    puts "      确认 UART 1 已路由到 MIO48/49"
    puts "    → 或者 UART 走的是 EMIO (PL 引脚)?"
}

# ---- [8] 下载并运行程序 ----
puts "\n[8] 下载 ELF..."
dow D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/build/crypto_test_app.elf

puts "\n[9] 启动程序..."
con

puts "\n✓ 程序运行中 - 观察串口 UART1"
puts "========== 完成 =========="
