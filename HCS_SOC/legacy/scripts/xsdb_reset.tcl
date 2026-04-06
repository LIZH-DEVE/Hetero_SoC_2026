# 完全重置并重新加载
puts "========== 完全系统重置 =========="

puts "\n[1] 断开连接..."
catch {disconnect}

puts "\n[2] 重新连接..."
connect

puts "\n[3] 选择目标..."
targets -set -nocase -filter {name =~ "arm*#0"}

puts "\n[4] 系统复位..."
rst -system

puts "\n[5] 等待稳定..."
after 1000

puts "\n[6] 编程 FPGA..."
fpga -f D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit

puts "\n[7] PS 初始化..."
source D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/platform/hw/ps7_init.tcl
ps7_init
ps7_post_config

puts "\n[8] 读取硬件状态（不下载程序）..."
set status [mrd -value 0x43C00008]
puts [format "REG_STATUS = 0x%08x" $status]
set fp [expr {($status >> 20) & 0xFFF}]
puts [format "硬件指纹 = 0x%03x" $fp]

if {$fp == 0xACE} {
    puts "\n✓ 硬件指纹正确! 位流已正确加载。"
    puts "\n现在可以安全下载程序:"
    puts "dow D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/build/crypto_test_app.elf"
    puts "con"
} else {
    puts "\n✗ 硬件指纹错误! 需要重新生成位流。"
}

puts "\n========== 完成 =========="
