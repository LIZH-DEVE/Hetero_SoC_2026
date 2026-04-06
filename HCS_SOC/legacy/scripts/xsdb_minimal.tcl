# 极简脚本 v2.0 - 回归原始流程 (不做任何额外寄存器操作)
# 之前旧 ELF 用这个流程是可以正常输出的

puts "===== [1] 连接 ====="
connect
targets -set -nocase -filter {name =~ "arm*#0"}

puts "===== [2] 系统重置 ====="
rst -system
after 2000

puts "===== [3] 烧录位流 ====="
fpga -f "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit"
after 1000

puts "===== [4] PS 初始化 (ps7_init 会自动处理时钟/隔离门/DDR) ====="
source "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/platform/hw/ps7_init.tcl"
ps7_init
ps7_post_config
after 500

puts "===== [5] 下载 ELF ====="
dow "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/build/crypto_test_app.elf"

puts "===== [6] 运行 ====="
con

puts "===== 完成! 观察 PuTTY ====="
