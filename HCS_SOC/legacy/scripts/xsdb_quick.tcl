# 快速诊断脚本 - 检查 0x21d60 位置
puts "\n========== 快速诊断 =========="

# 停止 CPU
stop

# 读取 PC
puts "\n当前 PC 位置:"
rrd pc

# 反汇编当前位置
puts "\n反汇编 0x21d60 附近:"
dis 0x21d60 10

# 读取加密硬件状态
puts "\n读取加密硬件状态寄存器:"
set status [mrd -value 0x43C00008]
puts [format "REG_STATUS = 0x%08x" $status]

set fingerprint [expr {($status >> 20) & 0xFFF}]
puts [format "硬件指纹 = 0x%03x" $fingerprint]

if {$fingerprint == 0xACE} {
    puts "✓ 硬件指纹正确!"
} else {
    puts "✗ 硬件指纹错误!"
}

# 检查是否在 Xil_DCacheDisable 中
puts "\n检查符号表:"
puts "查找 Xil_DCacheDisable 函数地址..."

puts "\n========== 诊断完成 =========="
puts "\n建议: 0x21d60 很可能在 cache 禁用函数中"
puts "解决方案: 注释掉 main.c 中的 Xil_DCacheDisable() 和 Xil_ICacheDisable()"
