# ==============================================================================
# Day 20: 物理层时序收敛 - 约束文件
# Task 19.1: Critical Path Optimization & Documentation
# Updated: Multi-instance crypto bridge support
# ==============================================================================

# ==============================================================================
# 0. 主时钟约束
# ==============================================================================
# PS FCLK_CLK0 - 100MHz system clock (from Zynq Processing System)
# This clock is provided by the PS and connected to PL fabric via AXI clock

# If using PS-provided clock (recommended for Zynq):
create_clock -period 10.000 -name FCLK_CLK0 [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ "*processing_system7_0*"}] -filter REF_PIN_NAME == FCLK_CLK0]

# Alternative: If you have an external clock input port:
# create_clock -period 10.000 -name sys_clk [get_ports sys_clk]

# ==============================================================================
# 1. 跨时钟域 (CDC) 约束
# ==============================================================================
# Async FIFO - 同步器约束 (Gray code crossings)
set_property ASYNC_REG TRUE [get_cells -hierarchical -filter {NAME =~ "*sync_*" && IS_SEQUENTIAL}]

# Gray code pointer crossings - false paths (already synchronized)
set_false_path -from [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ "*gray_sync*" && PRIMITIVE_LEVEL == "MACRO"}] -filter REF_PIN_NAME == D] \
                  -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ "*gray_sync*" && PRIMITIVE_LEVEL == "MACRO"}] -filter REF_PIN_NAME == Q]

# Async FIFO - pointer read/write
set_max_delay -datapath_only 2.0 \
    -from [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ "*async_fifo*" && NAME =~ "*wr_ptr*"}] -filter REF_PIN_NAME == Q] \
    -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ "*async_fifo*" && NAME =~ "*rd_ptr*"}] -filter REF_PIN_NAME == D]

# ==============================================================================
# 2. 物理区域约束 (Pblock) - Updated for multi-instance
# ==============================================================================
# 创建 Crypto Core 的物理区域 (expanded for 16 instances)
create_pblock crypto_core_region
add_cells_to_pblock [get_pblocks crypto_core_region] [get_cells -hierarchical -filter {NAME =~ "*crypto_bridge_top*" || NAME =~ "*u_crypto_engine*"}]

# 扩展区域以容纳更多实例 (16 instances need more area)
resize_pblock crypto_core_region -add {SLICE_X0Y0:SLICE_X119Y199}

# 刷新物理约束
update_pblock crypto_core_region

# ==============================================================================
# 3. 关键路径优化约束
# ==============================================================================
# Crypto Core - 高优先级布局
set_property STEP bel [get_pblocks crypto_core_region]
set_property OPT_MODE "PerfOptimized_high" [get_cells -hierarchical -filter {NAME =~ "*crypto_bridge_top*" || NAME =~ "*u_crypto_engine*"}]

# AES/SM4 轮函数 - 关键路径
set_property MAX_FANOUT 4 [get_cells -hierarchical -filter {NAME =~ "*aes_round*" || NAME =~ "*sm4_round*"}]
set_property DONT_TOUCH TRUE [get_cells -hierarchical -filter {NAME =~ "*pipeline_reg*"}]

# Multi-instance: 控制信号高扇出
set_property MAX_FANOUT 8 [get_cells -hierarchical -filter {NAME =~ "*inst_start*" || NAME =~ "*sched_*"}]

# ==============================================================================
# 4. AXI4 时序约束
# ==============================================================================
# AXI Master 时钟域
create_generated_clock -name axi_clk -source [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ "*processing_system7_0*"}] -filter REF_PIN_NAME == FCLK_CLK0] \
    -multiply_by 1 -divide_by 1 [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ "*axi_master*"}] -filter REF_PIN_NAME == clk]

# AXI 总线时序约束
set_input_delay -clock axi_clk -max 2.0 [get_ports -filter {NAME =~ "m_axi_*ready" || NAME =~ "m_axi_*resp"}]
set_output_delay -clock axi_clk -max 2.0 [get_ports -filter {NAME =~ "m_axi_*valid" || NAME =~ "m_axi_*data" || NAME =~ "m_axi_*addr" || NAME =~ "m_axi_*len"}]

# Outstanding transactions - FIFO depth constraints
set_property ALLOW_COMBINE FALSE [get_cells -hierarchical -filter {NAME =~ "*outstanding*"}]

# ==============================================================================
# 5. 多周期路径约束
# ==============================================================================
# Crypto Core - 多周期路径 (允许3个时钟周期完成一轮加密)
set_multicycle_path -setup 3 -to [get_cells -hierarchical -filter {NAME =~ "*aes_result*" || NAME =~ "*sm4_result*" || NAME =~ "*inst_result*"}]
set_multicycle_path -hold 2 -to [get_cells -hierarchical -filter {NAME =~ "*aes_result*" || NAME =~ "*sm4_result*" || NAME =~ "*inst_result*"}]

# Scheduler - 多周期路径
set_multicycle_path -setup 2 -to [get_cells -hierarchical -filter {NAME =~ "*sched_next*" || NAME =~ "*sched_current*"}]
set_multicycle_path -hold 1 -to [get_cells -hierarchical -filter {NAME =~ "*sched_next*" || NAME =~ "*sched_current*"}]

# ==============================================================================
# 6. 时钟关系约束
# ==============================================================================
set_clock_groups -asynchronous -group [get_clocks FCLK_CLK0] -group [get_clocks axi_clk]

# ==============================================================================
# 7. 局部布局约束
# ==============================================================================
# DMA Master Engine - 靠近 BRAM
create_pblock dma_region
add_cells_to_pblock [get_pblocks dma_region] [get_cells -hierarchical -filter {NAME =~ "*u_dma_master*"}]
resize_pblock dma_region -add {SLICE_X60Y0:SLICE_X119Y99}

# PBM Controller - 靠近 BRAM
create_pblock pbm_region
add_cells_to_pblock [get_pblocks pbm_region] [get_cells -hierarchical -filter {NAME =~ "*u_pbm*"}]
resize_pblock pbm_region -add {BRAM18_X2Y0:BRAM18_X3Y39}

# ==============================================================================
# 8. 路由优化约束
# ==============================================================================
# 关键信号 - 使用高性能布线资源
set_property ROUTE_PRIORITY HIGH [get_nets -hierarchical -filter {NAME =~ "*aes_key*" || NAME =~ "*sm4_key*"}]

# FastPath 信号 - 最小化延迟
set_property MAX_DELAY 1.5 [get_nets -hierarchical -filter {NAME =~ "*fastpath*"}]

# Multi-instance: 调度器信号优化
set_property MAX_DELAY 2.0 [get_nets -hierarchical -filter {NAME =~ "*sched_*" && !NAME =~ "*_i"}]

# ==============================================================================
# 9. FIFO 约束
# ==============================================================================
# Mid FIFO - 深度优化
set_property RAM_STYLE BLOCK [get_cells -hierarchical -filter {NAME =~ "*u_mid_fifo*"}]

# Output FIFO - 深度优化
set_property RAM_STYLE BLOCK [get_cells -hierarchical -filter {NAME =~ "*u_out_fifo*"}]

# ==============================================================================
# 10. 约束验证命令
# ==============================================================================
# report_timing -setup -max_paths 10 -sort_by slack -file timing_setup.rpt
# report_timing -hold -max_paths 10 -sort_by slack -file timing_hold.rpt
# report_utilization -file utilization.rpt
# report_drc -file drc.rpt
