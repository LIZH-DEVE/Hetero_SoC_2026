# ============================================================
# 一键完整流程 (最终版)
# 修复: UART时钟(DIVISOR=20→75MHz) + 波特率(BRGR=93@75MHz→115200)
# ============================================================
puts "========== 完整初始化 + UART修复(75MHz) =========="

# [1] 重连
puts "\n[1] 重新连接..."
catch {disconnect}
after 500
connect
targets -set -nocase -filter {name =~ "arm*#0"}

# [2] 系统复位
puts "\n[2] 系统复位..."
rst -system
after 1000

# [3] 编程 FPGA
puts "\n[3] 编程 FPGA..."
fpga -f D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit

# [4] PS 基础初始化
puts "\n[4] PS 基础初始化 (ps7_init)..."
source D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/platform/hw/ps7_init.tcl
ps7_init
ps7_post_config
after 200

# [5] 手动使能 UART 时钟 (ps7_init.tcl 未配置)
puts "\n[5] 手动使能 UART 时钟..."
mwr -force 0xF8000008 0x0000DF0D

# APER_CLK_CTRL: 打开 bit20(UART0) + bit21(UART1)
set aper [mrd -value 0xF800012C]
mwr -force 0xF800012C [expr {$aper | 0x00300000}]
puts [format "    APER_CLK_CTRL = 0x%08x" [mrd -value 0xF800012C]]

# UART_CLK_CTRL: SRCSEL=IO_PLL, DIVISOR=20 → 75MHz, 两路都开
# 0x00001403: bits[1:0]=11(both on), bits[5:4]=00(IO_PLL), bits[13:8]=0x14=20
mwr -force 0xF8000154 0x00001403
puts [format "    UART_CLK_CTRL = 0x%08x (DIVISOR=20→75MHz)" [mrd -value 0xF8000154]]

# MIO48(UART1 TX) / MIO49(UART1 RX)
mwr -force 0xF80007C0 0x000016E0
mwr -force 0xF80007C4 0x000016E1
# MIO14(UART0 TX) / MIO15(UART0 RX)
mwr -force 0xF8000738 0x000016E0
mwr -force 0xF800073C 0x000016E1

mwr -force 0xF8000004 0x0000767B
after 50

# [6] 初始化 UART1 控制器 — 115200 @ 75MHz
puts "\n[6] 初始化 UART1: 115200 baud @ 75MHz..."
puts "    公式: 75,000,000 / (93 × 7) = 115,434 bps ≈ 115200 ✓"
mwr 0xE0001000 0x00000003   ;# RXRST + TXRST
after 20
mwr 0xE0001004 0x00000020   ;# 8N1, Normal mode
mwr 0xE0001018 93           ;# BRGR = 93  (关键修复：原来错误的62改为93)
mwr 0xE000101C 6            ;# BDIV = 6
mwr 0xE0001000 0x00000114   ;# TX_EN + RX_EN
after 20

# [7] 验证
puts "\n[7] 验证 UART1 状态:"
set sr [mrd -value 0xE000102C]
puts [format "    UART1_SR  = 0x%08x" $sr]
puts [format "    UART1_BRGR= %d" [mrd -value 0xE0001018]]
puts [format "    UART1_BDIV= %d" [mrd -value 0xE000101C]]
if {($sr >> 3) & 1} {
    puts "    TXEMPTY=1 ✓ UART 就绪"
} else {
    puts "    !! SR 异常，请检查"
}

# [8] 直写测试字符
puts "\n[8] 直写 'HELLO\\r\\n' 到 UART1 FIFO..."
foreach b {0x48 0x45 0x4C 0x4C 0x4F 0x0D 0x0A} { mwr 0xE0001030 $b }
puts "    → PuTTY 应出现: HELLO"
after 1000

# [9] 下载 ELF
puts "\n[9] 下载 ELF..."
dow D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/build/crypto_test_app.elf

# [10] 运行
puts "\n[10] 启动程序..."
con

puts "\n✓ 完成！PuTTY 应出现 'ABC' 和测试 banner"
puts "=========================================="
