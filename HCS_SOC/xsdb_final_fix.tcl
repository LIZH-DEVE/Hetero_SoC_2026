# 终极修复脚本 v1.4 (正确顺序: 重置优先)
# 核心修复: rst -system 必须在所有操作之前，否则 DAP 报 0xF0000021

puts "===== [1] 连接与系统重置 ====="
connect
targets -set -nocase -filter {name =~ "arm*#0"}
rst -system
after 2000

puts "===== [2] 烧录 FPGA 位流 ====="
fpga -f "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit"
after 1000

puts "===== [3] PS 初始化 (DDR/时钟/外设) ====="
source "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/platform/hw/ps7_init.tcl"
ps7_init
ps7_post_config
after 500

puts "===== [4] 解锁 SLCR 并强开隔离门 ====="
mwr 0xf8000008 0xdf0d      ;# SLCR 解锁密码
mwr 0xf8000900 0x0000000F  ;# 开启 PS-PL 全部隔离门
mwr 0xf8000240 0x00000000  ;# 释放 PL 复位
after 100

puts "===== [5] 探测 AXI 硬件指纹 ====="
configparams force-mem-access 1
set result [mrd -value 0x43C00008]
puts [format ">>> PL REG_STATUS = 0x%08x" $result]
set fp [expr {($result >> 20) & 0xFFF}]
if { $fp == 0xACE } {
    puts ">>> 硬件指纹 0xACE 匹配! AXI 链路已打通!"
} else {
    puts [format ">>> 指纹 = 0x%03x (非 0xACE), 位流可能未更新" $fp]
}

puts "===== [6] 修复 UART1 (100MHz -> 115200) ====="
mwr 0xE0001000 0x00000028  ;# Disable
mwr 0xE0001018 124         ;# CD
mwr 0xE000101C 6           ;# BDIV
mwr 0xE0001000 0x00000114  ;# Enable
after 50

puts "===== [7] 直写验证字符到 PuTTY ====="
foreach b {0x0D 0x0A 0x41 0x58 0x49 0x5F 0x4F 0x4B 0x0D 0x0A} {
    mwr 0xE0001030 $b
}
after 100

puts "===== [8] 下载 ELF 并运行 ====="
dow "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/build/crypto_test_app.elf"
con
puts "===== 全部完成! 观察 PuTTY 和上方的指纹读取结果 ====="
