# 一体化脚本: 重连 + 初始化 + UART 测试 + 运行程序
puts "========== 完整诊断流程 =========="

# 1. 重连
puts "\n[1] 重新连接..."
catch {disconnect}
after 500
connect

# 2. 选择目标
puts "\n[2] 选择 ARM 目标..."
targets -set -nocase -filter {name =~ "arm*#0"}

# 3. 系统复位
puts "\n[3] 系统复位..."
rst -system
after 1000

# 4. 编程 FPGA
puts "\n[4] 编程 FPGA..."
fpga -f D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit

# 5. PS 初始化
puts "\n[5] PS 初始化..."
source D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/platform/hw/ps7_init.tcl
ps7_init
ps7_post_config

# 6. CPU 保持停止，直接测试两个 UART
puts "\n[6] ===== UART 硬件直写测试 (CPU 停止状态) ====="
puts "    注意: CPU 未运行，直接由调试器写 UART FIFO"
puts ""

# 读 UART0 状态
set u0sr [mrd -value 0xE000002C]
puts [format "    UART0 SR (0xE000002C) = 0x%08x" $u0sr]
set u0txfull  [expr {($u0sr >> 4) & 1}]
set u0txempty [expr {($u0sr >> 3) & 1}]
puts [format "      → TXFULL=%d  TXEMPTY=%d" $u0txfull $u0txempty]

# 读 UART1 状态
set u1sr [mrd -value 0xE000102C]
puts [format "    UART1 SR (0xE000102C) = 0x%08x" $u1sr]
set u1txfull  [expr {($u1sr >> 4) & 1}]
set u1txempty [expr {($u1sr >> 3) & 1}]
puts [format "      → TXFULL=%d  TXEMPTY=%d" $u1txfull $u1txempty]

puts ""
puts "    写 'U0\\r\\n' 到 UART0..."
mwr 0xE0000030 0x55  ;# 'U'
mwr 0xE0000030 0x30  ;# '0'
mwr 0xE0000030 0x0D  ;# CR
mwr 0xE0000030 0x0A  ;# LF

after 100

puts "    写 'U1\\r\\n' 到 UART1..."
mwr 0xE0001030 0x55  ;# 'U'
mwr 0xE0001030 0x31  ;# '1'
mwr 0xE0001030 0x0D  ;# CR
mwr 0xE0001030 0x0A  ;# LF

puts ""
puts "    ★ 请立刻看 PuTTY 串口:"
puts "      - 出现 'U0' → 串口线接的是 UART0，请改用 UART0 串口"
puts "      - 出现 'U1' → 串口线接的是 UART1，UART 硬件正常"
puts "      - 什么都没有 → 串口线/波特率/COM口有问题"
puts ""
puts "    等待 3 秒让你观察..."
after 3000

# 7. 下载程序
puts "\n[7] 下载程序..."
dow D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/build/crypto_test_app.elf

# 8. 运行
puts "\n[8] 启动程序..."
con

puts "\n✓ 程序运行中，请观察串口"
puts "========== 完成 =========="
