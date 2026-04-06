# XSDB 调试脚本 - 检查 CPU 挂起状态
# 使用方法: 在 XSDB 中执行 source xsdb_debug.tcl

puts "\n========== CPU 状态诊断 =========="

# 1. 检查 CPU 是否在运行
puts "\n[1] 检查 CPU 状态..."
state

# 2. 停止 CPU
puts "\n[2] 停止 CPU..."
stop

# 3. 读取 PC 寄存器
puts "\n[3] 读取 PC (程序计数器)..."
set pc_raw [rrd pc]
# 提取十六进制地址
regexp {0x[0-9a-fA-F]+} $pc_raw pc
puts "PC = $pc"

# 4. 读取通用寄存器
puts "\n[4] 读取通用寄存器..."
puts "R0:"
set r0 [rrd r0]
puts $r0
puts "R1:"
set r1 [rrd r1]
puts $r1
puts "R2:"
set r2 [rrd r2]
puts $r2
puts "R3:"
set r3 [rrd r3]
puts $r3
puts "\nSP (R13):"
set sp [rrd sp]
puts $sp
puts "LR (R14):"
set lr [rrd lr]
puts $lr

# 5. 反汇编当前 PC 位置
puts "\n[5] 反汇编当前位置 (PC 附近 20 条指令)..."
dis $pc 20

# 6. 检查是否在 main 函数
puts "\n[6] 检查符号信息..."
puts "尝试查找当前函数..."

# 7. 读取加密硬件状态寄存器
puts "\n[7] 读取加密硬件状态寄存器 (0x43C00008)..."
set status [mrd -value 0x43C00008]
puts "REG_STATUS = [format 0x%08x $status]"
set fingerprint [expr {($status >> 20) & 0xFFF}]
puts "硬件指纹 = [format 0x%03x $fingerprint]"
if {$fingerprint == 0xACE} {
    puts "✓ 硬件指纹正确 (0xACE)"
} else {
    puts "✗ 硬件指纹错误! 期望 0xACE, 实际 [format 0x%03x $fingerprint]"
}

# 8. 检查栈内容
puts "\n[8] 检查栈顶内容..."
set sp_val [rrd -value sp]
puts "栈指针 SP = [format 0x%08x $sp_val]"
mrd $sp_val 8

# 9. 检查 DDR 是否可访问
puts "\n[9] 测试 DDR 访问 (0x100000)..."
mrd 0x100000 4

puts "\n========== 诊断完成 =========="
puts "\n建议操作:"
puts "1. 如果 PC 在 0x1cfc0 附近，说明挂在初始化代码中"
puts "2. 如果硬件指纹不是 0xACE，需要重新烧录位流"
puts "3. 如果 DDR 读取失败，ps7_init 可能有问题"
puts "4. 使用 'con' 命令继续运行，或 'stp' 单步执行\n"
