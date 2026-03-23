# 调试脚本 - 检查 UART 状态
# 日期: 2026-03-15

puts "===== [DEBUG] 检查当前状态 ====="

# 检查 MIO 配置
puts "MIO48 (UART1 TX): [mrd 0xF80007C0]"
puts "MIO49 (UART1 RX): [mrd 0xF80007C4]"

# 检查 UART 控制寄存器
puts "UART_CR: [mrd 0xE0001000]"
puts "UART_MR: [mrd 0xE0001004]"
puts "UART_SR: [mrd 0xE000102C]"

# 检查时钟
puts "APER_CLK_CTRL: [mrd 0xF800012C]"

puts "===== [DEBUG] 重新配置 UART ====="

# 解锁 SLCR
mwr 0xF8000008 0x0000DF0D
puts "SLCR unlocked"

# 使能 UART1 APB 时钟
mwr 0xF800012C 0x016C004D
puts "UART1 clock enabled"

# 配置 MIO48 (TX) - L3_SEL=111, Pull-up, Slow Slew
mwr 0xF80007C0 0x00001607
puts "MIO48 configured"

# 配置 MIO49 (RX) - L3_SEL=111, Pull-up, Slow Slew
mwr 0xF80007C4 0x00001607
puts "MIO49 configured"

# 锁定 SLCR
mwr 0xF8000004 0x0000767B
puts "SLCR locked"

after 100

# 配置 UART1 控制器
# 1. 禁用 UART
mwr 0xE0001000 0x00000000
after 10

# 2. 设置波特率 (115200 @ 50MHz)
# BAUDDIV = 50000000 / (16 * 115200) - 1 = 26.13 ≈ 27
# BAUDGEN = 0x1B (27)
mwr 0xE0001018 0x0000007B
puts "Baud rate set"

# 3. 设置模式: 正常模式, 8N1
mwr 0xE0001004 0x00000020
puts "Mode set"

# 4. 使能 TX/RX
mwr 0xE0001000 0x00000014
puts "UART enabled"

after 100

puts "===== [DEBUG] 验证配置 ====="
puts "MIO48: [mrd 0xF80007C0]"
puts "MIO49: [mrd 0xF80007C4]"
puts "UART_CR: [mrd 0xE0001000]"
puts "UART_SR: [mrd 0xE000102C]"

puts "===== [DEBUG] 直接发送测试字符 ====="
# 直接向 UART FIFO 写入字符
mwr 0xE0001030 0x00000041
puts "Sent 'A' to UART FIFO"

after 100

puts "===== [DEBUG] 下载程序并运行 ====="
dow "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/BACKUP_UART_WORKING_20260315/crypto_test_app.elf"
con

puts "===== 完成 ====="
