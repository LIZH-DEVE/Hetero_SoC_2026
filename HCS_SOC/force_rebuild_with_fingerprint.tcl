# 强制重新综合 IP 并生成包含硬件指纹的位流
# 用于修复硬件指纹被优化为 0x000 的问题

puts "=========================================="
puts "强制重建位流 - 包含硬件指纹 0xACE"
puts "=========================================="

# 打开项目
puts "\n[1/6] 打开 Vivado 项目..."
open_project "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr"

# 删除 IP 综合缓存，强制重新综合
puts "\n[2/6] 删除 IP 综合缓存..."
set ip_cache_dir "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.cache/ip"
if {[file exists $ip_cache_dir]} {
    file delete -force $ip_cache_dir
    puts "已删除 IP 缓存目录: $ip_cache_dir"
}

# 删除 crypto_accel_axi IP 的综合运行
puts "\n[3/6] 重置 IP 综合运行..."
set ip_synth_runs [get_runs -filter {IS_SYNTHESIS && SRCSET =~ "*crypto_accel_axi*"}]
foreach run $ip_synth_runs {
    puts "重置运行: $run"
    reset_run $run
}

# 更新 IP 目录中的文件
puts "\n[4/6] 更新 IP 目录..."
update_ip_catalog -rebuild

# 重新生成 Block Design
puts "\n[5/6] 重新生成 Block Design..."
set bd_files [get_files -filter {FILE_TYPE == "Block Designs"}]
foreach bd_file $bd_files {
    puts "生成 Block Design: $bd_file"
    generate_target all [get_files $bd_file]
}

# 运行综合和实现
puts "\n[6/6] 运行综合和实现..."
reset_run synth_1
reset_run impl_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1
puts "综合完成"

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "实现完成"

# 检查位流文件
set bitstream_file "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.runs/impl_1/design_1_wrapper.bit"
if {[file exists $bitstream_file]} {
    set timestamp [clock format [file mtime $bitstream_file] -format "%Y-%m-%d %H:%M:%S"]
    puts "\n=========================================="
    puts "位流生成成功！"
    puts "文件: $bitstream_file"
    puts "时间: $timestamp"
    puts "=========================================="
} else {
    puts "\n=========================================="
    puts "错误：位流文件未生成"
    puts "=========================================="
}

close_project
