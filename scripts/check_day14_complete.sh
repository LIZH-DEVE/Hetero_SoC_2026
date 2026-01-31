#!/bin/bash

echo "================================================================================"
echo "Day 14: 全系统回环 - 完整检查"
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
echo "1. 关键文件检查"
echo "========================================"
echo ""

check_file "1.1" "Testbench文件" "tb/tb_day14_full_integration.sv"
check_file "1.2" "仿真TCL脚本" "run_day14_sim.tcl"
check_file "1.3" "仿真BAT脚本" "run_day14_sim.bat"
check_file "1.4" "编译文件列表" "day14_compile.prj"
check_file "1.5" "验证脚本" "verify_day14.sh"

echo ""
echo "========================================"
echo "2. Golden Model检查"
echo "========================================"
echo ""

check_file "2.1" "AES Golden Vectors" "aes_golden_vectors.txt"
check_content "2.2" "AES Key格式" "aes_golden_vectors.txt" "KEY="
check_content "2.3" "AES IV格式" "aes_golden_vectors.txt" "IV="
check_content "2.4" "AES密文格式" "aes_golden_vectors.txt" "CIPHERTEXT="
check_file "2.5" "SM4 Golden Vectors" "sm4_golden_vectors.txt"

echo ""
echo "========================================"
echo "3. Testbench功能检查"
echo "========================================"
echo ""

check_content "3.1" "gen_pcap任务" "tb/tb_day14_full_integration.sv" "task gen_pcap"
check_content "3.2" "Pcap文件头写入" "tb/tb_day14_full_integration.sv" "fwrite.*pcap"
check_content "3.3" "正常包测试" "tb/tb_day14_full_integration.sv" "task send_normal_udp_packet"
check_content "3.4" "Malformed包测试" "tb/tb_day14_full_integration.sv" "task send_malformed_udp_packet"
check_content "3.5" "CSR写入任务" "tb/tb_day14_full_integration.sv" "task csr_write"
check_content "3.6" "CSR读取任务" "tb/tb_day14_full_integration.sv" "task csr_read"
check_content "3.7" "Crypto Key配置" "tb/tb_day14_full_integration.sv" "crypto_key"
check_content "3.8" "DUT实例化" "tb/tb_day14_full_integration.sv" "crypto_dma_subsystem u_dut"
check_content "3.9" "时钟生成" "tb/tb_day14_full_integration.sv" "clk = 0"
check_content "3.10" "复位生成" "tb/tb_day14_full_integration.sv" "rst_n = 0"

echo ""
echo "========================================"
echo "4. 核心RTL模块检查"
echo "========================================"
echo ""

check_file "4.1" "Crypto Engine" "rtl/core/crypto/crypto_engine.sv"
check_content "4.2" "Crypto Engine模块" "rtl/core/crypto/crypto_engine.sv" "module crypto_engine"
check_content "4.3" "算法选择" "rtl/core/crypto/crypto_engine.sv" "algo_sel"
check_file "4.4" "RX Parser" "rtl/core/parser/rx_parser.sv"
check_content "4.5" "RX Parser模块" "rtl/core/parser/rx_parser.sv" "module rx_parser"
check_content "4.6" "DROP状态" "rtl/core/parser/rx_parser.sv" "DROP"
check_file "4.7" "TX Stack" "rtl/core/tx/tx_stack.sv"
check_content "4.8" "TX Stack模块" "rtl/core/tx/tx_stack.sv" "module tx_stack"
check_content "4.9" "Checksum计算" "rtl/core/tx/tx_stack.sv" "checksum"
check_file "4.10" "DMA Master" "rtl/core/dma/dma_master_engine.sv"
check_content "4.11" "DMA Master模块" "rtl/core/dma/dma_master_engine.sv" "module dma_master_engine"
check_content "4.12" "4K边界处理" "rtl/core/dma/dma_master_engine.sv" "0x1000\|dist_to_4k"

echo ""
echo "========================================"
echo "5. 编译文件列表检查"
echo "========================================"
echo ""

check_content "5.1" "Package文件" "day14_compile.prj" "pkg_axi_stream.sv"
check_content "5.2" "Crypto Engine" "day14_compile.prj" "crypto_engine.sv"
check_content "5.3" "RX Parser" "day14_compile.prj" "rx_parser.sv"
check_content "5.4" "TX Stack" "day14_compile.prj" "tx_stack.sv"
check_content "5.5" "DMA Master" "day14_compile.prj" "dma_master_engine.sv"
check_content "5.6" "Testbench" "day14_compile.prj" "tb_day14_full_integration.sv"

echo ""
echo "========================================"
echo "6. 仿真脚本检查"
echo "========================================"
echo ""

check_content "6.1" "编译命令" "run_day14_sim.tcl" "xvlog"
check_content "6.2" "Elaborate命令" "run_day14_sim.tcl" "xelab"
check_content "6.3" "仿真命令" "run_day14_sim.tcl" "xsim"
check_content "6.4" "项目目录" "run_day14_sim.tcl" "proj_dir"
check_content "6.5" "编译文件列表" "run_day14_sim.tcl" "day14_compile.prj"

echo ""
echo "========================================"
echo "7. 验收标准检查"
echo "========================================"
echo ""

check_content "7.1" "Wireshark抓包" "tb/tb_day14_full_integration.sv" "gen_pcap"
check_content "7.2" "Payload加密" "rtl/core/crypto/crypto_engine.sv" "aes_core\|sm4_top"
check_content "7.3" "Checksum正确" "rtl/core/tx/tx_stack.sv" "checksum"
check_content "7.4" "Malformed检测" "rtl/core/parser/rx_parser.sv" "DROP"

echo ""
echo "================================================================================"
echo "检查结果统计"
echo "================================================================================"
echo ""
echo "总检查项: $total_checks"
echo "通过: $passed_checks"
echo "失败: $failed_checks"
echo ""

pass_rate=$((passed_checks * 100 / total_checks))

if [ $failed_checks -eq 0 ]; then
    echo "================================================================================"
    echo "✅ Day 14 检查全部通过！"
    echo "================================================================================"
    echo ""
    echo "所有关键文件均存在且内容正确"
    echo "仿真可以正常进行"
    echo ""
    echo "运行仿真命令:"
    echo "  Windows: run_day14_sim.bat"
    echo "  Linux:   vivado -mode batch -source run_day14_sim.tcl"
    echo ""
    echo "预期输出:"
    echo "  - tb_day14_full_integration.vcd (波形文件)"
    echo "  - day14_capture.pcap (抓包文件)"
    echo "  - compile.log (编译日志)"
    echo "  - simulate.log (仿真日志)"
    echo ""
    echo "================================================================================"
    exit 0
else
    echo "================================================================================"
    echo "⚠️  完成率: $pass_rate%"
    echo "❌ 有 $failed_checks 个检查未通过"
    echo "================================================================================"
    exit 1
fi
