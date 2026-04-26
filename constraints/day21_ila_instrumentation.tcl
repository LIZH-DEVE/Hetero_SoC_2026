# ==============================================================================
# Day 21: 终极交付 - ILA Instrumentation TCL脚本
# Task 20.1: ILA Instrumentation
# 抓取 drop_reason, fastpath_active, axi_error
# ==============================================================================

# ==============================================================================
# 1. 创建ILA探针
# ==============================================================================

# ILA 1: Drop Statistics Monitor
create_debug_hub u_ila_hub
create_ila u_ila_drop_stats
set_property C_EN_DEPTH 1024 [get_debug_cores u_ila_drop_stats]
set_property C_TRIG_OUT_COUNT 0 [get_debug_cores u_ila_drop_stats]
set_property C_ADV_TRIGGER "NONE" [get_debug_cores u_ila_drop_stats]
set_property C_DATA_SAMPLE_RATE "Sample On Rising Edge" [get_debug_cores u_ila_drop_stats]

# 探针连接: Drop Statistics
connect_debug_port u_ila_drop_stats/clk [get_nets -hierarchical -filter {NAME =~ "*clk" && PRIMITIVE_LEVEL == "PORT"}]

# Drop Reason (3 bits)
connect_debug_port u_ila_drop_stats/probe0 [get_pins -hierarchical -filter {NAME =~ "*drop_reason*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_TYPE {Data Only} [get_debug_cores u_ila_drop_stats -filter PROBE_INDEX==0]
set_property PROBE_WIDTH 3 [get_debug_cores u_ila_drop_stats -filter PROBE_INDEX==0]

# Drop Counters (32 bits each)
connect_debug_port u_ila_drop_stats/probe1 [get_pins -hierarchical -filter {NAME =~ "*drop_cnt*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 32 [get_debug_cores u_ila_drop_stats -filter PROBE_INDEX==1]

connect_debug_port u_ila_drop_stats/probe2 [get_pins -hierarchical -filter {NAME =~ "*bad_align_cnt*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 32 [get_debug_cores u_ila_drop_stats -filter PROBE_INDEX==2]

connect_debug_port u_ila_drop_stats/probe3 [get_pins -hierarchical -filter {NAME =~ "*malformed_cnt*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 32 [get_debug_cores u_ila_drop_stats -filter PROBE_INDEX==3]

connect_debug_port u_ila_drop_stats/probe4 [get_pins -hierarchical -filter {NAME =~ "*runt_cnt*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 32 [get_debug_cores u_ila_drop_stats -filter PROBE_INDEX==4]

connect_debug_port u_ila_drop_stats/probe5 [get_pins -hierarchical -filter {NAME =~ "*giant_cnt*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 32 [get_debug_cores u_ila_drop_stats -filter PROBE_INDEX==5]

# ==============================================================================
# 2. FastPath Performance Monitor
# ==============================================================================

create_ila u_ila_fastpath
set_property C_EN_DEPTH 2048 [get_debug_cores u_ila_fastpath]
set_property C_TRIG_OUT_COUNT 0 [get_debug_cores u_ila_fastpath]
set_property C_ADV_TRIGGER "NONE" [get_debug_cores u_ila_fastpath]
set_property C_DATA_SAMPLE_RATE "Sample On Rising Edge" [get_debug_cores u_ila_fastpath]

# 探针连接: FastPath Stats
connect_debug_port u_ila_fastpath/clk [get_nets -hierarchical -filter {NAME =~ "*clk" && PRIMITIVE_LEVEL == "PORT"}]

# FastPath Active (1 bit)
connect_debug_port u_ila_fastpath/probe0 [get_pins -hierarchical -filter {NAME =~ "*fastpath_active*" || NAME =~ "*fast_path_active*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_TYPE {Data Only} [get_debug_cores u_ila_fastpath -filter PROBE_INDEX==0]
set_property PROBE_WIDTH 1 [get_debug_cores u_ila_fastpath -filter PROBE_INDEX==0]

# FastPath Counters (32 bits each)
connect_debug_port u_ila_fastpath/probe1 [get_pins -hierarchical -filter {NAME =~ "*fast_path_cnt*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 32 [get_debug_cores u_ila_fastpath -filter PROBE_INDEX==1]

connect_debug_port u_ila_fastpath/probe2 [get_pins -hierarchical -filter {NAME =~ "*bypass_cnt*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 32 [get_debug_cores u_ila_fastpath -filter PROBE_INDEX==2]

connect_debug_port u_ila_fastpath/probe3 [get_pins -hierarchical -filter {NAME =~ "*drop_cnt*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 32 [get_debug_cores u_ila_fastpath -filter PROBE_INDEX==3]

connect_debug_port u_ila_fastpath/probe4 [get_pins -hierarchical -filter {NAME =~ "*checksum_pass_cnt*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 32 [get_debug_cores u_ila_fastpath -filter PROBE_INDEX==4]

# ==============================================================================
# 3. AXI Performance Monitor
# ==============================================================================

create_ila u_ila_axi
set_property C_EN_DEPTH 4096 [get_debug_cores u_ila_axi]
set_property C_TRIG_OUT_COUNT 0 [get_debug_cores u_ila_axi]
set_property C_ADV_TRIGGER "NONE" [get_debug_cores u_ila_axi]
set_property C_DATA_SAMPLE_RATE "Sample On Rising Edge" [get_debug_cores u_ila_axi]

# 探针连接: AXI Stats
connect_debug_port u_ila_axi/clk [get_nets -hierarchical -filter {NAME =~ "*clk" && PRIMITIVE_LEVEL == "PORT"}]

# AXI Error (1 bit)
connect_debug_port u_ila_axi/probe0 [get_pins -hierarchical -filter {NAME =~ "*axi_error*" || NAME =~ "*o_error*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_TYPE {Data Only} [get_debug_cores u_ila_axi -filter PROBE_INDEX==0]
set_property PROBE_WIDTH 1 [get_debug_cores u_ila_axi -filter PROBE_INDEX==0]

# Outstanding Transactions (3 bits)
connect_debug_port u_ila_axi/probe1 [get_pins -hierarchical -filter {NAME =~ "*outstanding_cnt*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 3 [get_debug_cores u_ila_axi -filter PROBE_INDEX==1]

# Burst Counters (32 bits each)
connect_debug_port u_ila_axi/probe2 [get_pins -hierarchical -filter {NAME =~ "*burst_256_cnt*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 32 [get_debug_cores u_ila_axi -filter PROBE_INDEX==2]

connect_debug_port u_ila_axi/probe3 [get_pins -hierarchical -filter {NAME =~ "*burst_128_cnt*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 32 [get_debug_cores u_ila_axi -filter PROBE_INDEX==3]

connect_debug_port u_ila_axi/probe4 [get_pins -hierarchical -filter {NAME =~ "*burst_other_cnt*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 32 [get_debug_cores u_ila_axi -filter PROBE_INDEX==4]

connect_debug_port u_ila_axi/probe5 [get_pins -hierarchical -filter {NAME =~ "*split_cnt*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 32 [get_debug_cores u_ila_axi -filter PROBE_INDEX==5]

# AW Channel Signals
connect_debug_port u_ila_axi/probe6 [get_pins -hierarchical -filter {NAME =~ "*m_axi_awvalid*"}]
set_property PROBE_WIDTH 1 [get_debug_cores u_ila_axi -filter PROBE_INDEX==6]

connect_debug_port u_ila_axi/probe7 [get_pins -hierarchical -filter {NAME =~ "*m_axi_awready*"}]
set_property PROBE_WIDTH 1 [get_debug_cores u_ila_axi -filter PROBE_INDEX==7]

connect_debug_port u_ila_axi/probe8 [get_pins -hierarchical -filter {NAME =~ "*m_axi_awlen*"}]
set_property PROBE_WIDTH 8 [get_debug_cores u_ila_axi -filter PROBE_INDEX==8]

# ==============================================================================
# 4. Crypto Core Performance Monitor
# ==============================================================================

create_ila u_ila_crypto
set_property C_EN_DEPTH 512 [get_debug_cores u_ila_crypto]
set_property C_TRIG_OUT_COUNT 0 [get_debug_cores u_ila_crypto]
set_property C_ADV_TRIGGER "NONE" [get_debug_cores u_ila_crypto]
set_property C_DATA_SAMPLE_RATE "Sample On Rising Edge" [get_debug_cores u_ila_crypto]

# 探针连接: Crypto Stats
connect_debug_port u_ila_crypto/clk [get_nets -hierarchical -filter {NAME =~ "*clk" && PRIMITIVE_LEVEL == "PORT"}]

# Crypto Done (1 bit)
connect_debug_port u_ila_crypto/probe0 [get_pins -hierarchical -filter {NAME =~ "*done*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_TYPE {Data Only} [get_debug_cores u_ila_crypto -filter PROBE_INDEX==0]
set_property PROBE_WIDTH 1 [get_debug_cores u_ila_crypto -filter PROBE_INDEX==0]

# Crypto Busy (1 bit)
connect_debug_port u_ila_crypto/probe1 [get_pins -hierarchical -filter {NAME =~ "*busy*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 1 [get_debug_cores u_ila_crypto -filter PROBE_INDEX==1]

# Algo Select (1 bit)
connect_debug_port u_ila_crypto/probe2 [get_pins -hierarchical -filter {NAME =~ "*algo_sel*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 1 [get_debug_cores u_ila_crypto -filter PROBE_INDEX==2]

# ==============================================================================
# 5. PBM Resource Monitor
# ==============================================================================

create_ila u_ila_pbm
set_property C_EN_DEPTH 1024 [get_debug_cores u_ila_pbm]
set_property C_TRIG_OUT_COUNT 0 [get_debug_cores u_ila_pbm]
set_property C_ADV_TRIGGER "NONE" [get_debug_cores u_ila_pbm]
set_property C_DATA_SAMPLE_RATE "Sample On Rising Edge" [get_debug_cores u_ila_pbm]

# 探针连接: PBM Stats
connect_debug_port u_ila_pbm/clk [get_nets -hierarchical -filter {NAME =~ "*clk" && PRIMITIVE_LEVEL == "PORT"}]

# PBM Usage (14 bits)
connect_debug_port u_ila_pbm/probe0 [get_pins -hierarchical -filter {NAME =~ "*pbm_usage*" || NAME =~ "*buffer_usage*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 14 [get_debug_cores u_ila_pbm -filter PROBE_INDEX==0]

# Rollback Active (1 bit)
connect_debug_port u_ila_pbm/probe1 [get_pins -hierarchical -filter {NAME =~ "*rollback_active*" && PRIMITIVE_LEVEL == "INTERNAL"}]
set_property PROBE_WIDTH 1 [get_debug_cores u_ila_pbm -filter PROBE_INDEX==1]

# ==============================================================================
# 6. 触发条件设置
# ==============================================================================

# ILA 1: Drop Stats - 触发条件
set_property C_TRIG_TYPE "ADVANCED" [get_debug_cores u_ila_drop_stats]
set_property C_TRIG_EN_ADV_PORT {0} [get_debug_cores u_ila_drop_stats]
set_property C_TRIG_VALUE_ADV_PORT {1} [get_debug_cores u_ila_drop_stats]  # Drop Reason != 0
set_property C_TRIG_OPERATOR_ADV_PORT {==} [get_debug_cores u_ila_drop_stats]

# ILA 2: FastPath - 触发条件
set_property C_TRIG_TYPE "ADVANCED" [get_debug_cores u_ila_fastpath]
set_property C_TRIG_EN_ADV_PORT {0} [get_debug_cores u_ila_fastpath]
set_property C_TRIG_VALUE_ADV_PORT {1} [get_debug_cores u_ila_fastpath]  # FastPath Active
set_property C_TRIG_OPERATOR_ADV_PORT {==} [get_debug_cores u_ila_fastpath]

# ILA 3: AXI - 触发条件
set_property C_TRIG_TYPE "ADVANCED" [get_debug_cores u_ila_axi]
set_property C_TRIG_EN_ADV_PORT {0} [get_debug_cores u_ila_axi]
set_property C_TRIG_VALUE_ADV_PORT {1} [get_debug_cores u_ila_axi]  # AXI Error
set_property C_TRIG_OPERATOR_ADV_PORT {==} [get_debug_cores u_ila_axi]

# ==============================================================================
# 7. 导出ILA配置
# ==============================================================================

write_debug_probes -force ila_debug_probes.ltx

# ==============================================================================
# 8. 自动化ILA测试脚本
# ==============================================================================

proc test_ila_drop_stats {} {
    # 触发并捕获drop统计
    puts "Testing ILA Drop Stats..."
    run_hw_ila u_ila_drop_stats
    upload_hw_ila u_ila_drop_stats
    display_hw_ila_data u_ila_drop_stats
}

proc test_ila_fastpath {} {
    # 触发并捕获fastpath性能
    puts "Testing ILA FastPath..."
    run_hw_ila u_ila_fastpath
    upload_hw_ila u_ila_fastpath
    display_hw_ila_data u_ila_fastpath
}

proc test_ila_axi {} {
    # 触发并捕获AXI性能
    puts "Testing ILA AXI..."
    run_hw_ila u_ila_axi
    upload_hw_ila u_ila_axi
    display_hw_ila_data u_ila_axi
}

# ==============================================================================
# 9. 性能监控脚本
# ==============================================================================

proc monitor_performance {duration_ms} {
    # 监控指定时长的性能数据
    puts "Monitoring performance for ${duration_ms}ms..."

    # 运行ILA
    run_hw_ila u_ila_fastpath
    after $duration_ms

    # 上传数据
    upload_hw_ila u_ila_fastpath
    upload_hw_ila u_ila_axi

    # 显示统计
    set fastpath_cnt [get_property PROBE_DATA [get_debug_cores u_ila_fastpath -filter PROBE_INDEX==1]]
    set bypass_cnt [get_property PROBE_DATA [get_debug_cores u_ila_fastpath -filter PROBE_INDEX==2]]
    set burst_256_cnt [get_property PROBE_DATA [get_debug_cores u_ila_axi -filter PROBE_INDEX==2]]
    set burst_128_cnt [get_property PROBE_DATA [get_debug_cores u_ila_axi -filter PROBE_INDEX==3]]

    puts "FastPath Packets: $fastpath_cnt"
    puts "Bypass Packets: $bypass_cnt"
    puts "256-Beat Bursts: $burst_256_cnt"
    puts "128-Beat Bursts: $burst_128_cnt"
}
