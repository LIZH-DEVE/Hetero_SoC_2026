# 简化的诊断脚本
puts "停止 CPU..."
stop

puts "\n读取 PC:"
set pc_output [rrd pc]
puts $pc_output

puts "\n反汇编 0x100000 (程序入口):"
dis 0x100000 20

puts "\n读取加密硬件状态 (0x43C00008):"
set status [mrd -value 0x43C00008]
puts [format "STATUS = 0x%08x" $status]
set fp [expr {($status >> 20) & 0xFFF}]
puts [format "指纹 = 0x%03x (期望 0xACE)" $fp]

puts "\n测试 UART 寄存器 (0xE0001000):"
set uart_sr [mrd -value 0xE000102C]
puts [format "UART_SR = 0x%08x" $uart_sr]

puts "\n完成!"
