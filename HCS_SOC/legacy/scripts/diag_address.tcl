# 诊断 AXI 地址段名称
# 在 Vivado Tcl Console 中执行

open_bd_design [get_files design_1.bd]

puts "===== 当前所有已映射的地址段 ====="
set segments [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data]]
foreach seg $segments {
    set offset [get_property offset $seg]
    puts "Segment: $seg -> Offset: $offset"
}

puts "===== 检查 crypto_accel_axi_0 的所有引脚 ====="
set pins [get_bd_pins -of_objects [get_bd_cells crypto_accel_axi_0]]
foreach pin $pins {
    puts "Pin: $pin"
}

puts "===== 检查未映射的地址段 ====="
set unmapped [get_bd_addr_segs -filter {IS_EXCLUDED == 1 || MAP == ""}]
foreach seg $unmapped {
    puts "Unmapped: $seg"
}
