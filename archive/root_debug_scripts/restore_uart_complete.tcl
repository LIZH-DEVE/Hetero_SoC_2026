# 完整恢复脚本 - 包含 UART 配置
# 日期: 2026-03-15

puts "===== [1] 连接目标 ====="
connect
targets -set -nocase -filter {name =~ "arm*#0"}
stop

puts "===== [2] 烧录备份位流 ====="
fpga -f "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/BACKUP_UART_WORKING_20260315/design_1_wrapper.bit"
after 2000

puts "===== [3] PS 初始化 ====="
source "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/BACKUP_UART_WORKING_20260315/ps7_init.tcl"
ps7_init
ps7_post_config
after 500

puts "===== [4] 配置 UART1 (MIO48/MIO49) ====="
# 解锁 SLCR
mwr 0xF8000008 0x0000DF0D

# 使能 UART1 APB 时钟 (bit 21 = 1)
mwr 0xF800012C 0x016C004D

# 配置 MIO48/49 为 UART1 功能 (L3_SEL = 111 = 0x7)
mwr 0xF80007C0 0x00001607
mwr 0xF80007C4 0x00001607

# 锁定 SLCR
mwr 0xF8000004 0x0000767B
after 100

# 配置 UART1 控制器
mwr 0xE0001000 0x00000014
mwr 0xE0001018 0x0000007B
mwr 0xE0001034 0x00000006
mwr 0xE0001004 0x00000020
after 100

puts "===== [5] 验证配置 ====="
puts "MIO48: [mrd 0xF80007C0]"
puts "MIO49: [mrd 0xF80007C4]"
puts "UART_CR: [mrd 0xE0001000]"

puts "===== [6] 下载备份程序 ====="
dow "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/BACKUP_UART_WORKING_20260315/crypto_test_app.elf"

puts "===== [7] 运行程序 ====="
con

puts "===== 完成! 请检查 PuTTY (COM9, 115200) ====="
