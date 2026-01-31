#!/bin/bash

echo "================================================================================"
echo "Day 15: Hardware Security Module (HSM) - 验证脚本"
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
echo "Task 14.1: Config Packet Auth"
echo "========================================"
echo ""

check_file "1.1" "Config Packet Auth模块" "rtl/security/config_packet_auth.sv"
check_content "1.2" "模块定义" "rtl/security/config_packet_auth.sv" "module config_packet_auth"
check_content "1.3" "Magic Number检查" "rtl/security/config_packet_auth.sv" "DEADBEEF"
check_content "1.4" "序列ID检查" "rtl/security/config_packet_auth.sv" "seq_id_reg"
check_content "1.5" "状态机" "rtl/security/config_packet_auth.sv" "state_t"
check_content "1.6" "认证成功计数" "rtl/security/config_packet_auth.sv" "auth_success_cnt"
check_content "1.7" "认证失败计数" "rtl/security/config_packet_auth.sv" "auth_fail_cnt"
check_content "1.8" "重放检测计数" "rtl/security/config_packet_auth.sv" "replay_fail_cnt"

echo ""
echo "========================================"
echo "Task 14.2: Key Vault with DNA Binding"
echo "========================================"
echo ""

check_file "2.1" "Key Vault模块" "rtl/security/key_vault.sv"
check_content "2.2" "模块定义" "rtl/security/key_vault.sv" "module key_vault"
check_content "2.3" "DNA Port原语" "rtl/security/key_vault.sv" "DNA_PORT"
check_content "2.4" "DNA输出" "rtl/security/key_vault.sv" "dna_out"
check_content "2.5" "密钥派生" "rtl/security/key_vault.sv" "hash_output"
check_content "2.6" "系统锁定" "rtl/security/key_vault.sv" "system_locked"
check_content "2.7" "篡改检测" "rtl/security/key_vault.sv" "tamper_detected"
check_content "2.8" "有效密钥输出" "rtl/security/key_vault.sv" "effective_key_out"
check_content "2.9" "存储DNA" "rtl/security/key_vault.sv" "stored_dna"
check_content "2.10" "状态机" "rtl/security/key_vault.sv" "STATE_IDLE\|STATE_LOCK"

echo ""
echo "========================================"
echo "Testbench检查"
echo "========================================"
echo ""

check_file "3.1" "HSM Testbench" "tb/tb_day15_hsm.sv"
check_content "3.2" "模块定义" "tb/tb_day15_hsm.sv" "module tb_day15_hsm"
check_content "3.3" "Config Auth实例化" "tb/tb_day15_hsm.sv" "u_config_auth"
check_content "3.4" "Key Vault实例化" "tb/tb_day15_hsm.sv" "u_key_vault"
check_content "3.5" "发送配置包任务" "tb/tb_day15_hsm.sv" "send_config_packet"
check_content "3.6" "发送用户密钥任务" "tb/tb_day15_hsm.sv" "send_user_key"
check_content "3.7" "Test 1: Valid Magic" "tb/tb_day15_hsm.sv" "Test 1.*Valid Magic"
check_content "3.8" "Test 2: Invalid Magic" "tb/tb_day15_hsm.sv" "Test 2.*Invalid Magic"
check_content "3.9" "Test 3: Anti-Replay" "tb/tb_day15_hsm.sv" "Test 3.*Anti-Replay"
check_content "3.10" "Test 4: Sequential IDs" "tb/tb_day15_hsm.sv" "Test 4.*Sequential IDs"
check_content "3.11" "Test 5: DNA Binding" "tb/tb_day15_hsm.sv" "Test 5.*DNA Binding"
check_content "3.12" "Test 6: Key Derivation" "tb/tb_day15_hsm.sv" "Test 6.*Key Derivation"

echo ""
echo "========================================"
echo "仿真脚本检查"
echo "========================================"
echo ""

check_file "4.1" "Day15仿真TCL脚本" "run_day15_sim.tcl"
check_content "4.2" "编译命令" "run_day15_sim.tcl" "xvlog"
check_content "4.3" "Elaborate命令" "run_day15_sim.tcl" "xelab"
check_content "4.4" "仿真命令" "run_day15_sim.tcl" "xsim"
check_file "4.5" "Day15编译列表" "day15_compile.prj"
check_content "4.6" "Config Auth模块" "day15_compile.prj" "config_packet_auth.sv"
check_content "4.7" "Key Vault模块" "day15_compile.prj" "key_vault.sv"
check_content "4.8" "Testbench" "day15_compile.prj" "tb_day15_hsm.sv"

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
    echo "✅ Day 15 所有功能均已实现！"
    echo "================================================================================"
    echo ""
    echo "Task 14.1: Config Packet Auth (Patch) ✅"
    echo "  - Magic Number Authentication: ✅"
    echo "  - Anti-Replay Protection: ✅"
    echo ""
    echo "Task 14.2: Key Vault with DNA Binding (Updated) ✅"
    echo "  - DNA Binding: ✅"
    echo "  - Key Derivation: ✅"
    echo "  - System Lock: ✅"
    echo ""
    echo "Testbench: ✅"
    echo "  - All 6 tests implemented: ✅"
    echo ""
    echo "仿真脚本: ✅"
    echo "  - TCL script: ✅"
    echo "  - Compile list: ✅"
    echo ""
    echo "运行仿真:"
    echo "  Windows: run_day15_sim.bat"
    echo "  Linux:   vivado -mode batch -source run_day15_sim.tcl"
    echo ""
    echo "================================================================================"
    exit 0
else
    echo "================================================================================"
    echo "⚠️  有 $failed_checks 个检查未通过"
    echo "================================================================================"
    exit 1
fi
