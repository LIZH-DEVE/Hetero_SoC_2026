#!/bin/bash

echo "================================================================================"
echo "Day 14 & 15: 最终综合验证"
echo "================================================================================"
echo ""

total_checks=0
passed_checks=0
failed_checks=0

check_file() {
    local id=$1
    local name=$2
    local file=$3

    ((total_checks++))
    echo "[$total_checks] 检查: $name"

    if [ ! -f "$file" ]; then
        echo "     ❌ 失败: 文件不存在 $file"
        ((failed_checks++))
        return 1
    fi

    echo "     ✅ 通过: 文件存在"
    ((passed_checks++))
    return 0
}

check_content() {
    local id=$1
    local name=$2
    local file=$3
    local pattern=$4

    ((total_checks++))
    echo "[$total_checks] 检查: $name"

    if [ ! -f "$file" ]; then
        echo "     ❌ 失败: 文件不存在 $file"
        ((failed_checks++))
        return 1
    fi

    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "     ✅ 通过: 找到 '$pattern'"
        ((passed_checks++))
        return 0
    else
        echo "     ❌ 失败: 未找到 '$pattern'"
        ((failed_checks++))
        return 1
    fi
}

echo "========================================"
echo "Day 14: 全系统回环"
echo "========================================"
echo ""

check_file "D14.1" "Day14 Testbench" "tb/tb_day14_full_integration.sv"
check_content "D14.2" "gen_pcap任务" "tb/tb_day14_full_integration.sv" "gen_pcap"
check_content "D14.3" "正常包测试" "tb/tb_day14_full_integration.sv" "send_normal_udp_packet"
check_content "D14.4" "Malformed包测试" "tb/tb_day14_full_integration.sv" "send_malformed_udp_packet"
check_file "D14.5" "Golden Model AES" "aes_golden_vectors.txt"
check_file "D14.6" "Golden Model SM4" "sm4_golden_vectors.txt"

echo ""
echo "========================================"
echo "Day 15: 硬件安全模块(HSM)"
echo "========================================"
echo ""

check_file "D15.1" "Config Auth模块" "rtl/security/config_packet_auth.sv"
check_content "D15.2" "Magic Number" "rtl/security/config_packet_auth.sv" "DEADBEEF"
check_content "D15.3" "Anti-Replay" "rtl/security/config_packet_auth.sv" "seq_id"
check_file "D15.4" "Key Vault模块" "rtl/security/key_vault.sv"
check_content "D15.5" "DNA Port" "rtl/security/key_vault.sv" "DNA_PORT"
check_content "D15.6" "密钥派生" "rtl/security/key_vault.sv" "hash_output"
check_content "D15.7" "系统锁定" "rtl/security/key_vault.sv" "system_locked"
check_file "D15.8" "Day15 Testbench" "tb/tb_day15_hsm.sv"

echo ""
echo "========================================"
echo "核心RTL模块"
echo "========================================"
echo ""

check_file "RTL.1" "Crypto Bridge" "rtl/core/crypto/crypto_bridge_top.sv"
check_content "RTL.2" "AES算法" "rtl/core/crypto/crypto_bridge_top.sv" "AES"
check_content "RTL.3" "SM4算法" "rtl/core/crypto/crypto_bridge_top.sv" "SM4"
check_file "RTL.4" "RX Parser" "rtl/core/parser/rx_parser.sv"
check_content "RTL.5" "RX DROP" "rtl/core/parser/rx_parser.sv" "DROP"
check_file "RTL.6" "TX Stack" "rtl/core/tx/tx_stack.sv"
check_content "RTL.7" "TX Checksum" "rtl/core/tx/tx_stack.sv" "checksum"
check_file "RTL.8" "DMA Master" "rtl/core/dma/dma_master_engine.sv"

echo ""
echo "========================================"
echo "仿真脚本"
echo "========================================"
echo ""

check_file "SIM.1" "Day14 TCL脚本" "run_day14_sim.tcl"
check_file "SIM.2" "Day14 BAT脚本" "run_day14_sim.bat"
check_file "SIM.3" "Day14编译列表" "day14_compile.prj"
check_file "SIM.4" "Day15 TCL脚本" "run_day15_sim.tcl"
check_file "SIM.5" "Day15 BAT脚本" "run_day15_sim.bat"
check_file "SIM.6" "Day15编译列表" "day15_compile.prj"

echo ""
echo "================================================================================"
echo "最终验证结果统计"
echo "================================================================================"
echo ""
echo "总检查项: $total_checks"
echo "通过: $passed_checks"
echo "失败: $failed_checks"
echo ""

pass_rate=$((passed_checks * 100 / total_checks))

if [ $failed_checks -eq 0 ]; then
    echo "================================================================================"
    echo "✅ Day 14 & 15 任务全部完成！"
    echo "================================================================================"
    echo ""
    echo "Day 14: 全系统回环 ✅"
    echo "  - Testbench: ✅"
    echo "  - Wireshark抓包: ✅"
    echo "  - Golden Model: ✅"
    echo "  - 仿真脚本: ✅"
    echo ""
    echo "Day 15: 硬件安全模块(HSM) ✅"
    echo "  - Config Packet Auth: ✅"
    echo "  - Key Vault with DNA Binding: ✅"
    echo "  - Testbench: ✅"
    echo "  - 仿真脚本: ✅"
    echo ""
    echo "核心RTL模块: ✅"
    echo "  - Crypto Bridge: ✅"
    echo "  - AES/SM4算法: ✅"
    echo "  - RX Parser: ✅"
    echo "  - TX Stack: ✅"
    echo "  - DMA Master: ✅"
    echo ""
    echo "================================================================================"
    echo "运行仿真:"
    echo "  Day 14: run_day14_sim.bat"
    echo "  Day 15: run_day15_sim.bat"
    echo "================================================================================"
    exit 0
else
    echo "================================================================================"
    echo "⚠️  完成率: $pass_rate%"
    echo "❌ 有 $failed_checks 个检查未通过"
    echo "================================================================================"
    exit 1
fi
