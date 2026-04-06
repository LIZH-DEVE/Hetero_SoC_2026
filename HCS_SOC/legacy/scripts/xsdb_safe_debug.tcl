# 安全诊断级启动脚本
# 此脚本烧录位流和 ELF 后，让处理器停留在程序入口，绝不自动运行！
connect
targets -set -nocase -filter {name =~ "arm*#0"}
rst -system

# 1. 烧录位流
fpga -f "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit"

# 2. PS 初始化
source D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/platform/hw/ps7_init.tcl
ps7_init
ps7_post_config

# 3. 下载 ELF
dow "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/build/crypto_test_app.elf"

puts "===== 启动环境已就绪 ====="
puts "当前 CPU 处于 STOP 状态，停在入口处。"
puts "-------------------------------------"
puts "请在 xsdb 命令行执行以下两步诊断："
puts "1. 输入: rrd pc （查看起始 PC 是否为 0x00100000）"
puts "2. 输入: step （单步执行一条指令，看是否能动）"
puts "如果上面正常，尝试输入: con （继续运行，看看到底卡死在哪）"
