#!/bin/bash

echo "=========================================="
echo "Hetero_SoC 2026 - 任务执行验证"
echo "=========================================="
echo ""

error_count=0
pass_count=0

# 检查函数
check_file() {
    local file=$1
    local desc=$2
    
    if [ -f "$file" ]; then
        local size=$(wc -l < "$file" 2>/dev/null || echo "0")
        echo "✅ $desc: $file ($size lines)"
        ((pass_count++))
    else
        echo "❌ $desc: 文件不存在 $file"
        ((error_count++))
    fi
}

# 检查文件内容
check_content() {
    local file=$1
    local pattern=$2
    local desc=$3
    
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "✅ $desc"
        ((pass_count++))
    else
        echo "❌ $desc: 未找到 '$pattern'"
        ((error_count++))
    fi
}

echo "Phase 1: 协议立法与总线基座 (Day 2-4)"
echo "-------------------------------------------"

# Task 1.1
check_file "rtl/inc/pkg_axi_stream.sv" "Task 1.1: SystemVerilog Package"
check_content "rtl/inc/pkg_axi_stream.sv" "ERR_BAD_ALIGN" "  - ERR_BAD_ALIGN定义"
check_content "rtl/inc/pkg_axi_stream.sv" "ERR_MALFORMED" "  - ERR_MALFORMED定义"
check_content "rtl/inc/pkg_axi_stream.sv" "AXI_BURST_LIMIT.*256" "  - AXI_BURST_LIMIT=256"
check_content "rtl/inc/pkg_axi_stream.sv" "ALIGN_MASK_64B.*6'h3F" "  - ALIGN_MASK_64B定义"

# Task 1.2
check_file "rtl/core/axil_csr.sv" "Task 1.2: CSR Design"
check_content "rtl/core/axil_csr.sv" "i_acl_inc" "  - i_acl_inc端口"
check_content "rtl/core/axil_csr.sv" "o_acl_cnt" "  - o_acl_cnt端口"
check_content "rtl/core/axil_csr.sv" "reg_acl_cnt" "  - reg_acl_cnt寄存器"
check_content "rtl/core/axil_csr.sv" "ACL Counter Increment" "  - ACL递增逻辑"
check_content "rtl/core/axil_csr.sv" "8'h44.*reg_acl_cnt" "  - 0x44写case"
check_content "rtl/core/axil_csr.sv" "8'h44.*s_axil_rdata.*reg_acl_cnt" "  - 0x44读case"

# Task 1.3
check_file "tb/axi_master_bfm.sv" "Task 1.3: BFM Verification"
check_content "tb/axi_master_bfm.sv" "check_alignment" "  - check_alignment task"
check_content "tb/axi_master_bfm.sv" "4K boundary" "  - 4K boundary检查"

# Task 2.1
check_file "rtl/core/dma/dma_master_engine.sv" "Task 2.1: Master FSM & Burst Logic"
check_content "rtl/core/dma/dma_master_engine.sv" "dist_to_4k" "  - dist_to_4k计算"
check_content "rtl/core/dma/dma_master_engine.sv" "burst_bytes_calc" "  - burst_bytes_calc"
check_content "rtl/core/dma/dma_master_engine.sv" "addr_unaligned.*i_base_addr\[2:0\]" "  - 对齐检查"

# Task 2.2
check_content "rtl/core/dma/dma_master_engine.sv" "INCR" "Task 2.2: Single-ID Ordering"

# Task 2.3
check_file "tb/virtual_ddr_model.sv" "Task 2.3: Virtual DDR Model"
check_content "tb/virtual_ddr_model.sv" "random_delay" "  - 随机延迟"
check_content "tb/virtual_ddr_model.sv" "MIN_LATENCY.*MAX_LATENCY" "  - 延迟范围"

# Task 3.1
check_file "tb/tb_full_system_verification.sv" "Task 3.1: Full-Link Simulation"
check_content "tb/tb_full_system_verification.sv" "test_alignment_check" "  - alignment检查测试"

echo ""
echo "Phase 2: 极速算力引擎 (Day 5-8)"
echo "-------------------------------------------"

# Task 4.1
check_file "rtl/core/gearbox_128_to_32.sv" "Task 4.1: Width Gearbox"

# Task 4.2
check_file "rtl/core/crypto/crypto_engine.sv" "Task 4.2: Crypto Core"
check_file "rtl/core/crypto/aes_core.sv" "  - AES Core"
check_file "rtl/core/crypto/sm4_encdec.v" "  - SM4 Core"

# Task 5.1
check_content "rtl/core/crypto/crypto_engine.sv" "din.*r_iv" "Task 5.1: IV Logic"

# Task 5.2
check_file "rtl/core/async_fifo.sv" "Task 5.2: CDC Integration"

# Task 6.1
check_file "rtl/top/packet_dispatcher.sv" "Task 6.1: Dispatcher"
check_content "rtl/top/packet_dispatcher.sv" "MODE_TUSER" "  - MODE_TUSER定义"
check_content "rtl/top/packet_dispatcher.sv" "tuser.*path" "  - tuser分发逻辑"

# Task 6.2
check_file "rtl/flow/credit_manager.sv" "Task 6.2: Flow Control"
check_content "rtl/flow/credit_manager.sv" "credits" "  - credits管理"

# Task 7.1
check_file "rtl/core/pbm/pbm_controller.sv" "Task 7.1: SRAM Controller"
check_content "rtl/core/pbm/pbm_controller.sv" "ALLOC_META" "  - ALLOC_META状态"

# Task 7.2
check_content "rtl/core/pbm/pbm_controller.sv" "ROLLBACK" "Task 7.2: Atomic Reservation"

echo ""
echo "Phase 3: 智能网卡子系统 (Day 9-14)"
echo "-------------------------------------------"

# Task 8.1
check_content "HCS_SOC/HCS_SOC.gen/sources_1/bd/system/hdl/system_wrapper.v" "axi_ethernet" "Task 8.1: MAC IP Integration"

# Task 8.2
check_file "rtl/core/parser/rx_parser.sv" "Task 8.2: RX Parser"
check_content "rtl/core/parser/rx_parser.sv" "udp_len.*ip_total_len" "  - 长度检查"
check_content "rtl/core/parser/rx_parser.sv" "payload_len.*16" "  - 对齐检查"

# Task 8.3
check_file "rtl/core/parser/arp_responder.sv" "Task 8.3: ARP Responder"

# Task 9.1
check_file "rtl/core/tx/tx_stack.sv" "Task 9.1: Checksum Offload"

# Task 9.2
check_content "rtl/core/tx/tx_stack.sv" "padding" "Task 9.2: TX Builder"

# Task 10.1-10.2
check_content "rtl/core/crypto/crypto_dma_subsystem.sv" "ring" "Task 10.1-10.2: HW Init & Ring Pointer"

# Task 11.1-11.3
check_file "rtl/core/dma/dma_desc_fetcher.sv" "Task 11.1-11.3: DMA Integration"
check_file "rtl/core/dma/dma_s2mm_mm2s_engine.sv" "  - S2MM/MM2S Engine"

echo ""
echo "工具和Testbench"
echo "-------------------------------------------"

check_file "gen_vectors.py" "Golden Model"
check_content "gen_vectors.py" "AES-128-CBC" "  - AES-128-CBC支持"
check_content "gen_vectors.py" "SM4-CBC" "  - SM4-CBC支持"
check_file "aes_golden_vectors.txt" "  - AES向量文件"
check_file "sm4_golden_vectors.txt" "  - SM4向量文件"

check_file "tb/tb_full_system_verification.sv" "Full System Testbench"
check_content "tb/tb_full_system_verification.sv" "test_csr_rw" "  - CSR测试"
check_content "tb/tb_full_system_verification.sv" "test_dispatcher_tuser" "  - Dispatcher测试"

check_file "run_full_sim.bat" "仿真脚本"
check_file "run_full_sim.tcl" "  - Tcl脚本"

echo ""
echo "=========================================="
echo "验证结果统计"
echo "=========================================="
echo "通过: $pass_count"
echo "失败: $error_count"
echo ""

if [ $error_count -eq 0 ]; then
    echo "✅ 所有任务已严格执行！"
else
    echo "❌ 有 $error_count 个任务未完成或有问题"
fi
echo "=========================================="

exit $error_count
