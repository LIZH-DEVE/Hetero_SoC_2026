# 修复 Block Design 并绕过 IP 打包机制的终极脚本
# 1. 打开项目并恢复 Block Design
open_project -quiet "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.xpr"
open_bd_design "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/HCS_SOC.srcs/sources_1/bd/design_1/design_1.bd"

# 2. 删除损坏的 IP
catch {delete_bd_objs [get_bd_cells crypto_accel_axi_0]}

# 3. 将 IP 代码作为“普通本地源码”直接添加到 Vivado 工程
# 这样不仅解决了打包损坏问题，还能让 Vivado 以后 100% 自动追踪代码的更新
add_files -norecurse -scan_for_includes "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/ip_repo/crypto_accel_axi_1_0/hdl/crypto_accel_axi.v"
add_files -norecurse -scan_for_includes "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/ip_repo/crypto_accel_axi_1_0/hdl/crypto_accel_axi_slave_lite_v1_0_S00_AXI.v"
update_compile_order -fileset sources_1

# 4. 把刚刚加入的模块以 Module Reference（RTL 模块直接引用）的方式放入 BD
# Module Reference 是 Vivado 非常强大的功能，能精准识别 AXI 接口，且无视任何缓存！
create_bd_cell -type module -reference crypto_accel_axi crypto_accel_axi_0

# 5. 自动连接 AXI 接口、时钟和复位
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/processing_system7_0/M_AXI_GP0} Slave {/crypto_accel_axi_0/s00_axi} ddr_seg {Auto} intc_ip {New AXI Interconnect} master_apm {0}}  [get_bd_intf_pins crypto_accel_axi_0/s00_axi]

# 6. 保存并重新生成
validate_bd_design
save_bd_design
generate_target all [get_files design_1.bd]

# 7. 重置综合并生成最新位流
puts "===== 启动全量综合与位流生成 ====="
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "===== 修复完毕，新位流已生成！ ====="
