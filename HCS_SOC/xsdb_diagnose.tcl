# XSDB 调试脚本 - 用于诊断连接问题
# 2026-03-16

puts "===== XSDB 连接诊断 ====="

# 连接到硬件服务器
puts "\n[1] 连接到硬件服务器..."
connect

# 列出所有可用目标
puts "\n[2] 列出所有可用目标..."
targets

# 尝试不同的目标选择方式
puts "\n[3] 尝试选择目标..."

# 方法 1: 选择第一个 ARM 目标
set arm_targets [targets -filter {name =~ "*ARM*"}]
if {[llength $arm_targets] > 0} {
    puts "找到 ARM 目标: $arm_targets"
    targets -set -filter {name =~ "*ARM*"}
} else {
    puts "未找到 ARM 目标"
}

# 方法 2: 选择 APU
set apu_targets [targets -filter {name =~ "*APU*"}]
if {[llength $apu_targets] > 0} {
    puts "找到 APU 目标: $apu_targets"
    targets -set -filter {name =~ "*APU*"}
} else {
    puts "未找到 APU 目标"
}

# 方法 3: 选择 Cortex-A9
set cortex_targets [targets -filter {name =~ "*Cortex*"}]
if {[llength $cortex_targets] > 0} {
    puts "找到 Cortex 目标: $cortex_targets"
    targets -set -filter {name =~ "*Cortex*"}
} else {
    puts "未找到 Cortex 目标"
}

# 显示当前目标
puts "\n[4] 当前目标:"
targets

puts "\n===== 诊断完成 ====="
puts "如果看到 'whole scan chain' 说明 FPGA 未配置或 JTAG 连接有问题"
puts "解决方案："
puts "1. 在 Vivado Hardware Manager 中先打开硬件服务器"
puts "2. 在 Hardware Manager 中加载位流"
puts "3. 然后再运行 XSDB"
