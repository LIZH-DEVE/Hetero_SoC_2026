# UART 测试脚本 - 便携版本
# 使用方法：
#   1. 将整个 uart_test_package 文件夹复制到新电脑
#   2. 在 XSDB 中 cd 到该文件夹
#   3. 运行: source run_test.tcl
#
# 注意：如果路径不同，请修改下方的 package_dir 变量

# ===== 配置区域 =====
# 修改这里的路径为你的实际路径
set package_dir "D:/test_uart"

# ===== 脚本开始 =====
puts "=========================================="
puts "   UART 测试 - 便携版本"
puts "=========================================="
puts ""

puts "===== [1] 连接目标 ====="
connect
targets -set -nocase -filter {name =~ "arm*#0"}
stop

puts "===== [2] 烧录位流 ====="
set bit_file "$package_dir/design_1_wrapper.bit"
puts "位流文件: $bit_file"
fpga -f $bit_file
after 2000

puts "===== [3] PS 初始化 ====="
set ps7_file "$package_dir/ps7_init.tcl"
puts "PS7 文件: $ps7_file"
source $ps7_file
ps7_init
ps7_post_config
after 500

puts "===== [4] 配置 UART1 (MIO48/MIO49) ====="
mwr 0xF8000008 0x0000DF0D
mwr 0xF800012C 0x016C004D
mwr 0xF80007C0 0x00001607
mwr 0xF80007C4 0x00001607
mwr 0xF8000004 0x0000767B
after 100

mwr 0xE0001000 0x00000014
mwr 0xE0001018 0x0000007B
mwr 0xE0001034 0x00000006
mwr 0xE0001004 0x00000020
after 100

puts "===== [5] 验证配置 ====="
puts "MIO48: [mrd 0xF80007C0]"
puts "MIO49: [mrd 0xF80007C4]"
puts "UART_CR: [mrd 0xE0001000]"

puts "===== [6] 下载程序 ====="
set elf_file "$package_dir/crypto_test_app.elf"
puts "程序文件: $elf_file"
dow $elf_file

puts "===== [7] 运行程序 ====="
con

puts ""
puts "=========================================="
puts "   完成! 请检查 PuTTY (波特率 115200)"
puts "=========================================="
puts ""
puts "如果 PuTTY 无输出，请在 XSDB 中执行："
puts "  stop"
puts "  mwr 0xE0001030 0x00000048"
puts "  mwr 0xE0001030 0x00000069"
puts "  con"
puts ""
