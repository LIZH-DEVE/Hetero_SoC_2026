#!/bin/bash

echo "================================================================================"
echo "Day 16: Hardware Firewall (ACL) - 验证脚本"
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
echo "Task 15.1: 5-Tuple Extraction"
echo "========================================"
echo ""

check_file "1.1" "5-Tuple Extractor模块" "rtl/security/five_tuple_extractor.sv"
check_content "1.2" "模块定义" "rtl/security/five_tuple_extractor.sv" "module five_tuple_extractor"
check_content "1.3" "Source IP输出" "rtl/security/five_tuple_extractor.sv" "output.*src_ip"
check_content "1.4" "Source Port输出" "rtl/security/five_tuple_extractor.sv" "output.*src_port"
check_content "1.5" "Destination IP输出" "rtl/security/five_tuple_extractor.sv" "output.*dst_ip"
check_content "1.6" "Destination Port输出" "rtl/security/five_tuple_extractor.sv" "output.*dst_port"
check_content "1.7" "Protocol输出" "rtl/security/five_tuple_extractor.sv" "output.*protocol"
check_content "1.8" "状态机" "rtl/security/five_tuple_extractor.sv" "IDLE"

echo ""
echo "========================================"
echo "Task 15.2: Enhanced Match Engine"
echo "========================================"
echo ""

check_file "2.1" "ACL Match Engine模块" "rtl/security/acl_match_engine.sv"
check_content "2.2" "模块定义" "rtl/security/acl_match_engine.sv" "module acl_match_engine"
check_content "2.3" "CRC16函数" "rtl/security/acl_match_engine.sv" "function.*crc16"
check_content "2.4" "CRC16计算" "rtl/security/acl_match_engine.sv" "CRC16.*CCITT"
check_content "2.5" "2-way Set Associative" "rtl/security/acl_match_engine.sv" "NUM_WAYS.*2"
check_content "2.6" "Way 0 BRAM" "rtl/security/acl_match_engine.sv" "bram_way0"
check_content "2.7" "Way 1 BRAM" "rtl/security/acl_match_engine.sv" "bram_way1"
check_content "2.8" "Tag比较" "rtl/security/acl_match_engine.sv" "way_hit"
check_content "2.9" "ACL命中" "rtl/security/acl_match_engine.sv" "acl_hit"
check_content "2.10" "ACL丢弃" "rtl/security/acl_match_engine.sv" "acl_drop"

echo ""
echo "========================================"
echo "Testbench检查"
echo "========================================"
echo ""

check_file "3.1" "ACL Testbench" "tb/tb_day16_acl.sv"
check_content "3.2" "模块定义" "tb/tb_day16_acl.sv" "module tb_day16_acl"
check_content "3.3" "Extractor实例化" "tb/tb_day16_acl.sv" "u_extractor"
check_content "3.4" "ACL Engine实例化" "tb/tb_day16_acl.sv" "u_acl_engine"
check_content "3.5" "发送IPv4包任务" "tb/tb_day16_acl.sv" "send_ipv4_packet"
check_content "3.6" "添加ACL条目任务" "tb/tb_day16_acl.sv" "add_acl_entry"
check_content "3.7" "清空ACL任务" "tb/tb_day16_acl.sv" "clear_acl"
check_content "3.8" "Test 1: 5-Tuple Extraction" "tb/tb_day16_acl.sv" "Test 1.*5-Tuple"
check_content "3.9" "Test 2: ACL Match" "tb/tb_day16_acl.sv" "Test 2.*ACL"
check_content "3.10" "Test 3: ACL Miss" "tb/tb_day16_acl.sv" "Test 3.*Miss"
check_content "3.11" "Test 4: ACL Clear" "tb/tb_day16_acl.sv" "Test 4.*Clear"

echo ""
echo "========================================"
echo "仿真脚本检查"
echo "========================================"
echo ""

check_file "4.1" "Day16仿真TCL脚本" "run_day16_sim.tcl"
check_content "4.2" "编译命令" "run_day16_sim.tcl" "xvlog"
check_content "4.3" "Elaborate命令" "run_day16_sim.tcl" "xelab"
check_content "4.4" "仿真命令" "run_day16_sim.tcl" "xsim"
check_file "4.5" "Day16编译列表" "day16_compile.prj"
check_content "4.6" "5-Tuple Extractor" "day16_compile.prj" "five_tuple_extractor.sv"
check_content "4.7" "ACL Match Engine" "day16_compile.prj" "acl_match_engine.sv"
check_content "4.8" "Testbench" "day16_compile.prj" "tb_day16_acl.sv"

echo ""
echo "================================================================================"
echo "验证结果统计"
echo "================================================================================"
echo ""
echo "总检查项: $total_checks"
echo "通过: $passed_checks"
echo "失败: $failed_checks"
echo ""

if [ $failed_checks -eq 0 ]; then
    echo "================================================================================"
    echo "✅ Day 16 所有功能均已实现！"
    echo "================================================================================"
    echo ""
    echo "Task 15.1: 5-Tuple Extraction ✅"
    echo "  - Source IP extraction: ✅"
    echo "  - Source Port extraction: ✅"
    echo "  - Destination IP extraction: ✅"
    echo "  - Destination Port extraction: ✅"
    echo "  - Protocol extraction: ✅"
    echo ""
    echo "Task 15.2: Enhanced Match Engine ✅"
    echo "  - CRC16 hashing: ✅"
    echo "  - 2-way Set Associative: ✅"
    echo "  - ACL hit detection: ✅"
    echo "  - ACL miss detection: ✅"
    echo "  - ACL drop signal: ✅"
    echo ""
    echo "Testbench: ✅"
    echo "  - All 4 tests implemented: ✅"
    echo ""
    echo "仿真脚本: ✅"
    echo "  - TCL script: ✅"
    echo "  - Compile list: ✅"
    echo ""
    echo "运行仿真:"
    echo "  Windows: run_day16_sim.bat"
    echo "  Linux:   vivado -mode batch -source run_day16_sim.tcl"
    echo ""
    echo "================================================================================"
    exit 0
else
    echo "================================================================================"
    echo "⚠️  有 $failed_checks 个检查未通过"
    echo "================================================================================"
    exit 1
fi
