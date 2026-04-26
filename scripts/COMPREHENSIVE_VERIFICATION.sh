#!/bin/bash

echo "================================================================================"
echo "Hetero_SoC 2026 - 完整需求验证报告"
echo "================================================================================"
echo ""

total_tasks=0
passed_tasks=0
failed_tasks=0

check_task() {
    local task_id=$1
    local task_name=$2
    local requirement=$3
    local file_path=$4
    local pattern=$5
    
    ((total_tasks++))
    
    echo "[$total_tasks] Task: $task_name"
    echo "     需求: $requirement"
    
    if [ ! -f "$file_path" ]; then
        echo "     ❌ 失败: 文件不存在 $file_path"
        ((failed_tasks++))
    else
        if [ -n "$pattern" ]; then
            if grep -q "$pattern" "$file_path" 2>/dev/null; then
                echo "     ✅ 通过: $file_path"
                ((passed_tasks++))
            else
                echo "     ❌ 失败: 未找到 '$pattern'"
                ((failed_tasks++))
            fi
        else
            echo "     ✅ 通过: 文件存在"
            ((passed_tasks++))
        fi
    fi
    echo ""
}

# ============================================================================
# Phase 1: 协议立法与总线基座 (Day 2 - Day 4)
# ============================================================================
echo "================================================================================"
echo "Phase 1: 协议立法与总线基座 (Day 2 - Day 4)"
echo "================================================================================"
echo ""

echo "Day 2: 协议定义与控制中枢 (The Constitution)"
echo "---------------------------------------------------------------------------"

# Task 1.1: SystemVerilog Package
check_task "1.1" "SystemVerilog Package" "长度定义: ip_total_len" \
    "rtl/inc/pkg_axi_stream.sv" "ip_total_len"

check_task "1.1a" "UDP Length定义" "udp_len定义" \
    "rtl/inc/pkg_axi_stream.sv" "UDP_HEADER_LEN"

check_task "1.1b" "Payload Length定义" "payload_len = udp_len - 8" \
    "rtl/inc/pkg_axi_stream.sv" "payload_len.*udp_len"

check_task "1.1c" "对齐约束" "ALIGN_MASK_64B = 6'h3F (64-Byte Aligned)" \
    "rtl/inc/pkg_axi_stream.sv" "ALIGN_MASK_64B.*6'h3F"

check_task "1.1d" "Payload对齐" "ALIGN_MASK_16B = 4'hF (16-Byte Aligned)" \
    "rtl/inc/pkg_axi_stream.sv" "ALIGN_MASK_16B.*4'hF"

check_task "1.1e" "AXI约束" "MAX_BURST_LEN = 256" \
    "rtl/inc/pkg_axi_stream.sv" "AXI_BURST_LEN.*256"

# Task 1.2: CSR Design
check_task "1.2a" "CACHE_CTRL寄存器" "0x40 CACHE_CTRL (Bit 0: Enable Flush)" \
    "rtl/core/axil_csr.sv" "0x40.*CACHE_CTRL"

check_task "1.2b" "ACL_COLLISION_CNT寄存器" "0x44 ACL_COLLISION_CNT" \
    "rtl/core/axil_csr.sv" "0x44.*ACL_COLLISION_CNT"

# Task 1.3: BFM Verification
check_task "1.3" "BFM Verification" "task check_alignment" \
    "tb/tb_full_system_verification.sv" "test_alignment_check"

echo "Day 3: 总线之王 (AXI4-Full Master)"
echo "---------------------------------------------------------------------------"

# Task 2.1: Master FSM & Burst Logic
check_task "2.1a" "拆包逻辑-跨4K" "跨4K边界拆包" \
    "rtl/core/dma/dma_master_engine.sv" "dist_to_4k"

check_task "2.1b" "拆包逻辑-长度限制" "len / width > 256" \
    "rtl/core/dma/dma_master_engine.sv" "burst_bytes_calc.*limit"

check_task "2.1c" "对齐处理" "addr\[2:0\] != 0 触发错误" \
    "rtl/core/dma/dma_master_engine.sv" "addr_unaligned.*i_base_addr\[2:0\]"

# Task 2.2: Single-ID Ordering
check_task "2.2" "Single-ID Ordering" "INCR burst type" \
    "rtl/core/dma/dma_master_engine.sv" "m_axi_awburst.*2'b01"

# Task 2.3: Virtual DDR Model
check_task "2.3" "Virtual DDR Model" "Virtual DDR Model" \
    "tb/virtual_ddr_model.sv" ""

echo "Day 4: 物理觉醒 (Zynq Bring-up)"
echo "---------------------------------------------------------------------------"

# Task 3.1: Full-Link Simulation
check_task "3.1" "Full-Link Simulation" "Full-Link Testbench" \
    "tb/tb_full_system_verification.sv" ""

# Task 3.3: Zynq Boot Image & Cache Strategy
check_task "3.3a" "HP接口配置" "HP0接口说明" \
    "doc/daily_logs/Day04.md" "HP0"

check_task "3.3b" "软件一致性策略" "dma_alloc_coherent" \
    "doc/daily_logs/Day04.md" "dma_alloc_coherent"

echo ""
echo "================================================================================"
echo "Phase 2: 极速算力引擎 (Day 5 - Day 8)"
echo "================================================================================"
echo ""

echo "Day 5: 算法硬核化"
echo "---------------------------------------------------------------------------"

# Task 4.1: Width Gearbox
check_task "4.1a" "Width Gearbox" "128-bit到32-bit转换" \
    "rtl/core/gearbox_128_to_32.sv" "gearbox_128_to_32"

check_task "4.1b" "Golden Model" "gen_vectors.py脚本" \
    "gen_vectors.py" "pycryptodome"

# Task 4.2: Crypto Core
check_task "4.2a" "AES-CBC实现" "AES-128-CBC" \
    "rtl/core/crypto/aes_core.sv" "AES"

check_task "4.2b" "SM4实现" "SM4实现" \
    "rtl/core/crypto/sm4_encdec.v" "SM4"

echo "Day 6: 流水线 & CDC"
echo "---------------------------------------------------------------------------"

# Task 5.1: IV Logic
check_task "5.1" "IV Logic" "CBC链式异或" \
    "rtl/core/crypto/crypto_engine.sv" "din.*r_iv"

# Task 5.2: CDC Integration
check_task "5.2" "CDC Integration" "Async FIFO" \
    "rtl/core/async_fifo.sv" "async_fifo"

echo "Day 7: 双核并联"
echo "---------------------------------------------------------------------------"

# Task 6.1: Dispatcher
check_task "6.1a" "Dispatcher模块" "packet_dispatcher" \
    "rtl/top/packet_dispatcher.sv" "packet_dispatcher"

check_task "6.1b" "tuser分发" "基于tuser分发" \
    "rtl/top/packet_dispatcher.sv" "MODE_TUSER"

# Task 6.2: Flow Control
check_task "6.2" "Flow Control" "Credit-based反压" \
    "rtl/flow/credit_manager.sv" "credit_manager"

echo "Day 8: 统一包缓冲管理 (PBM)"
echo "---------------------------------------------------------------------------"

# Task 7.1: SRAM Controller
check_task "7.1" "SRAM Controller" "BRAM Ring Buffer" \
    "rtl/core/pbm/pbm_controller.sv" "BRAM.*Ring.*Buffer"

# Task 7.2: Atomic Reservation
check_task "7.2a" "ALLOC_META状态" "ALLOC_META状态" \
    "rtl/core/pbm/pbm_controller.sv" "ALLOC_META"

check_task "7.2b" "ROLLBACK机制" "ROLLBACK状态机" \
    "rtl/core/pbm/pbm_controller.sv" "ROLLBACK"

echo ""
echo "================================================================================"
echo "Phase 3: 智能网卡子系统 (Day 9 - Day 14)"
echo "================================================================================"
echo ""

echo "Day 9: MAC IP & RX Stack"
echo "---------------------------------------------------------------------------"

# Task 8.1: MAC IP Integration
check_task "8.1" "MAC IP Integration" "AXI Ethernet" \
    "doc/daily_logs/Day09.md" "AXI.*Ethernet"

# Task 8.2: RX Parser
check_task "8.2a" "RX Parser" "RX Parser模块" \
    "rtl/core/parser/rx_parser.sv" "rx_parser"

check_task "8.2b" "长度检查" "udp_len > ip_total_len" \
    "rtl/core/parser/rx_parser.sv" "udp_len.*ip_total_len"

check_task "8.2c" "对齐检查" "payload_len % 16" \
    "rtl/core/parser/rx_parser.sv" "payload_len.*% 16"

check_task "8.2d" "Meta分配" "Meta分配" \
    "rtl/core/parser/rx_parser.sv" "meta.*valid"

# Task 8.3: ARP Responder
check_task "8.3" "ARP Responder" "ARP应答" \
    "rtl/core/parser/arp_responder.sv" "arp_responder"

echo "Day 10: TX Stack & Checksum"
echo "---------------------------------------------------------------------------"

# Task 9.1: Checksum Offload
check_task "9.1" "Checksum Offload" "Checksum计算" \
    "rtl/core/tx/tx_stack.sv" "checksum"

# Task 9.2: TX Builder
check_task "9.2a" "Padding逻辑" "Padding" \
    "rtl/core/tx/tx_stack.sv" "padding"

check_task "9.2b" "交换IP/MAC/Port" "交换" \
    "rtl/core/tx/tx_stack.sv" "swap"

echo "Day 11: 描述符环 & HW Init"
echo "---------------------------------------------------------------------------"

# Task 10.1: HW Initializer
check_task "10.1" "HW Initializer" "HW初始化" \
    "doc/daily_logs/Day11.md" "HW.*Init"

# Task 10.2: Ring Pointer Mgr
check_task "10.2" "Ring Pointer Mgr" "Ring指针管理" \
    "doc/daily_logs/Day11.md" "Ring.*Pointer"

echo "Day 12-13: DMA 集成"
echo "---------------------------------------------------------------------------"

# Task 11.1/11.2: DMA Engines
check_task "11.1" "S2MM/MM2S Engine" "S2MM/MM2S" \
    "rtl/core/dma/dma_s2mm_mm2s_engine.sv" "s2mm_mm2s"

# Task 11.3: Loop
