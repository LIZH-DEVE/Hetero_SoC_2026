# 最简化初始化脚本 - 不使用 disconnect
# 直接执行，如果卡住请 Ctrl+C 后手动逐行执行

puts "===== [1] 连接 ====="
connect
targets -set -nocase -filter {name =~ "arm*#0"}
stop

puts "===== [2] 系统重置 ====="
rst -system
after 3000

puts "===== [3] 烧录位流 ====="
fpga -f "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit"
after 3000

puts "===== [4] PS 初始化 ====="
source "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/platform/hw/ps7_init.tcl"
ps7_init
ps7_post_config
after 500

puts "===== [5] 检查时钟 ====="
puts "UART_CLK: [mrd 0xF8000154]"
puts "AMBA_CLK: [mrd 0xF800012C]"

puts "===== [6] 配置 UART ====="
mwr 0xF8000008 0x0000DF0D
mwr 0xF8000154 0x00003F03
mwr 0xF8000004 0x0000767B
after 100
mwr 0xE0001000 0x00000014
mwr 0xE0001018 0x0000007B
mwr 0xE0001034 0x00000006
mwr 0xE0001004 0x00000020
after 100

puts "UART_CR: [mrd 0xE0001000]"

puts "===== [7] 发送测试 ====="
mwr 0xE0001030 0x0000004F
mwr 0xE0001030 0x0000004B
mwr 0xE0001030 0x0000000D
mwr 0xE0001030 0x0000000A
puts "已发送 OK，检查 PuTTY"

puts "===== [8] 运行程序 ====="
dow "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/build/crypto_test_app.elf"
con

puts "===== 完成 ====="
