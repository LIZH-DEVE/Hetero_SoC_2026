# ==============================================================================
# Day 20: 物理层时序收敛 - 约束文件
# Task 19.1: Critical Path Optimization & Documentation
# ==============================================================================

# ==============================================================================
# 1. 跨时钟域 (CDC) 约束
# ==============================================================================
# Task 19.1 CDC: 显式通过 set_false_path 或 set_max_delay 约束异步 FIFO

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
# 2. 物理区域约束 (Pblock)
# ==============================================================================
# Task 19.1 Pblock: 手动圈定 Crypto Core 的物理区域

# 创建 Crypto Core 的物理区域
create_pblock crypto_core_region
add_cells_to_pblock [get_cells -hierarchical -filter {NAME =~ "u_crypto_engine*"}] [get_pblocks crypto_core_region]

# 定义区域位置 (SLR0, 避免跨SLR)
# 根据实际FPGA设备调整坐标
resize_pblock crypto_core_region -add {SLICE_X0Y0:SLICE_X59Y99} \
        -add {DSP48E2_X0Y0:DSP48E2_X9Y39} \
        -add {BRAM18_X0Y0:BRAM18_X1Y19}

# 刷新物理约束
update_pblock crypto_core_region

# ==============================================================================
# 3. 关键路径优化约束
# ==============================================================================
# Task 19.1: 流水线切割后的约束

# Crypto Core - 高优先级布局
set_property STEP bel [get_pblocks crypto_core_region]
set_property OPT_MODE "PerfOptimized_high" [get_cells -hierarchical -filter {NAME =~ "u_crypto_engine*"}]

# AES/SM4 轮函数 - 关键路径
set_property MAX_FANOUT 4 [get_cells -hierarchical -filter {NAME =~ "*aes_round*" || NAME =~ "*sm4_round*"}]
set_property DONT_TOUCH TRUE [get_cells -hierarchical -filter {NAME =~ "*pipeline_reg*"}]

# ==============================================================================
# 4. AXI4 时序约束
# ==============================================================================
# Day 19 Task 18.2: Outstanding (Depth 4) 约束

# AXI Master 时钟域
create_generated_clock -name axi_clk -source [get_pins clk] \
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
set_multicycle_path -setup 3 -to [get_cells -hierarchical -filter {NAME =~ "*aes_result*" || NAME =~ "*sm4_result*"}]
set_multicycle_path -hold 2 -to [get_cells -hierarchical -filter {NAME =~ "*aes_result*" || NAME =~ "*sm4_result*"}]

# ==============================================================================
# 6. 时钟关系约束
# ==============================================================================
# Core 时钟 vs Bus 时钟 (125MHz vs 100MHz)
# Day 6 Task 5.2: CDC Integration

set_clock_groups -asynchronous -group [get_clocks -of_objects [get_ports clk]] \
                                    -group [get_clocks -of_objects [get_ports axi_clk]]

# ==============================================================================
# 7. 局部布局约束
# ==============================================================================
# DMA Master Engine - 靠近 BRAM
create_pblock dma_region
add_cells_to_pblock [get_cells -hierarchical -filter {NAME =~ "u_dma_master*"}] [get_pblocks dma_region]
resize_pblock dma_region -add {SLICE_X60Y0:SLICE_X119Y99}

# PBM Controller - 靠近 BRAM
create_pblock pbm_region
add_cells_to_pblock [get_cells -hierarchical -filter {NAME =~ "u_pbm*"}] [get_pblocks pbm_region]
resize_pblock pbm_region -add {BRAM18_X2Y0:BRAM18_X3Y39}

# ==============================================================================
# 8. 路由优化约束
# ==============================================================================
# 关键信号 - 使用高性能布线资源
set_property ROUTE_PRIORITY HIGH [get_nets -hierarchical -filter {NAME =~ "*aes_key*" || NAME =~ "*sm4_key*"}]

# FastPath 信号 - 最小化延迟
set_property MAX_DELAY 1.5 [get_nets -hierarchical -filter {NAME =~ "*fastpath*"}]

# ==============================================================================
# 9. 时钟分频约束
# ==============================================================================
# 如果需要分频时钟
create_generated_clock -name clk_div2 -source [get_pins clk] -divide_by 2 [get_pins -filter {IS_SEQUENTIAL} -of_objects [get_cells -filter {NAME =~ "*clk_div2*"}]]

# ==============================================================================
# 10. 约束验证
# ==============================================================================
# 报告违例
report_timing -setup -max_paths 10 -sort_by slack -file timing_setup.rpt
report_timing -hold -max_paths 10 -sort_by slack -file timing_hold.rpt
report_utilization -file utilization.rpt
