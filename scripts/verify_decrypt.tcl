# 解密功能验证脚本
# 验证AES和SM4加解密功能

set PROJ_DIR "d:/作业/期刊/Hetero_SoC_2026"
set SIM_DIR "$PROJ_DIR/sim_output/decrypt_verify"

# 创建仿真目录
file mkdir $SIM_DIR
cd $SIM_DIR

# 清理旧的仿真文件
file delete -force xsim.dir
file delete -force *.log
file delete -force *.pb
file delete -force *.jou

puts "=========================================="
puts "Step 1: Compiling Design Sources..."
puts "=========================================="

# 编译工具模块
xvlog -sv "$PROJ_DIR/rtl/inc/sync_fifo.sv"
xvlog -sv "$PROJ_DIR/rtl/core/gearbox_128_to_32.sv"

# 编译AES核心模块
xvlog "$PROJ_DIR/rtl/core/crypto/aes_sbox.v"
xvlog "$PROJ_DIR/rtl/core/crypto/aes_inv_sbox.v"
xvlog "$PROJ_DIR/rtl/core/crypto/aes_key_mem.v"
xvlog "$PROJ_DIR/rtl/core/crypto/aes_encipher_block.v"
xvlog "$PROJ_DIR/rtl/core/crypto/aes_decipher_block.v"
xvlog "$PROJ_DIR/rtl/core/crypto/aes_core.v"

# 编译SM4核心模块
xvlog "$PROJ_DIR/rtl/core/crypto/get_cki.v"
xvlog "$PROJ_DIR/rtl/core/crypto/sbox_replace.v"
xvlog "$PROJ_DIR/rtl/core/crypto/transform_for_encdec.v"
xvlog "$PROJ_DIR/rtl/core/crypto/transform_for_key_exp.v"
xvlog "$PROJ_DIR/rtl/core/crypto/one_round_for_encdec.v"
xvlog "$PROJ_DIR/rtl/core/crypto/one_round_for_key_exp.v"
xvlog "$PROJ_DIR/rtl/core/crypto/key_expansion.v"
xvlog "$PROJ_DIR/rtl/core/crypto/sm4_encdec.v"
xvlog "$PROJ_DIR/rtl/core/crypto/sm4_top.v"

# 编译加密引擎包装模块
xvlog -sv "$PROJ_DIR/rtl/core/crypto/crypto_core.sv"
xvlog -sv "$PROJ_DIR/rtl/core/crypto/crypto_engine.sv"

puts "=========================================="
puts "Step 2: Compiling Testbenches..."
puts "=========================================="

# 编译原有测试平台（验证兼容性）
xvlog -sv "$PROJ_DIR/tb/tb_crypto_engine.sv"

# 编译解密验证测试平台
xvlog -sv "$PROJ_DIR/tb/tb_decrypt_verification.sv"

puts "=========================================="
puts "Step 3: Elaborating..."
puts "=========================================="

# Elaborate 解密验证测试
xelab -debug typical tb_decrypt_verification -snapshot decrypt_verify_snap -timescale 1ns/1ps

puts "=========================================="
puts "Step 4: Running Decrypt Verification..."
puts "=========================================="

# 运行仿真
xsim decrypt_verify_snap -runall -log decrypt_verify.log

puts "=========================================="
puts "Step 5: Checking Results..."
puts "=========================================="

# 检查结果
set log_file [open "decrypt_verify.log" r]
set log_content [read $log_file]
close $log_file

if {[string match "*ALL TESTS PASSED*" $log_content]} {
    puts "\n*** SUCCESS: All decrypt tests passed! ***"
} elseif {[string match "*FAIL*" $log_content]} {
    puts "\n*** WARNING: Some tests failed. Check log for details. ***"
} else {
    puts "\n*** Check decrypt_verify.log for results ***"
}

puts "\n=========================================="
puts "Step 6: Running Original Encrypt Test..."
puts "=========================================="

# Elaborate and run original test for compatibility
xelab -debug typical tb_crypto_engine -snapshot encrypt_verify_snap -timescale 1ns/1ps
xsim encrypt_verify_snap -runall -log encrypt_verify.log

puts "\n=========================================="
puts "Verification Complete!"
puts "=========================================="
puts "Log files:"
puts "  - decrypt_verify.log"
puts "  - encrypt_verify.log"
