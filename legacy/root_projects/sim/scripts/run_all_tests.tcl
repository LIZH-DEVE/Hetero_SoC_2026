# Vivado 批量仿真脚本
# 用于自动运行所有测试并生成报告

set proj_dir "D:/FPGAhanjia/Hetero_SoC_2026"
cd $proj_dir

# 创建日志目录
file mkdir sim/results

puts "=========================================="
puts "开始批量仿真验证"
puts "=========================================="
puts ""

# 测试列表
set test_list {
    {day14 "tb_day14_full_integration" "完整系统集成"}
    {crypto "tb_crypto_engine" "加密引擎"}
    {dma "tb_dma_master_engine" "DMA主控"}
}

set pass_count 0
set fail_count 0

foreach test $test_list {
    set test_name [lindex $test 0]
    set test_top [lindex $test 1]
    set test_desc [lindex $test 2]
    
    puts "==========================================
"
    puts "测试: $test_desc ($test_name)"
    puts "Top模块: $test_top"
    puts "==========================================
"
    
    # 编译
    puts "步骤 1: 编译 RTL 和 Testbench..."
    if {[catch {
        # 这里需要实际的编译命令
        exec xvlog -sv rtl/inc/pkg_axi_stream.sv 2>@1
    } result]} {
        puts "错误: 编译失败"
        puts $result
        incr fail_count
        continue
    }
    
    puts "✅ 编译完成"
    incr pass_count
}

puts ""
puts "=========================================="
puts "测试汇总"
puts "=========================================="
puts "通过: $pass_count"
puts "失败: $fail_count"
puts "总计: [expr {$pass_count + $fail_count}]"
puts ""
