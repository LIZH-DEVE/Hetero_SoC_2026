# 简化的加密引擎仿真脚本
# 用于快速验证加密功能

# 编译所有需要的文件
xvlog -sv rtl/inc/pkg_axi_stream.sv

# 编译AES模块
xvlog rtl/core/crypto/aes_sbox.v
xvlog rtl/core/crypto/aes_inv_sbox.v
xvlog rtl/core/crypto/aes_key_mem.v
xvlog rtl/core/crypto/aes_encipher_block.v
xvlog rtl/core/crypto/aes_decipher_block.v
xvlog rtl/core/crypto/aes_core.v

# 编译SM4模块
xvlog rtl/core/crypto/get_cki.v
xvlog rtl/core/crypto/sbox_replace.v
xvlog rtl/core/crypto/transform_for_encdec.v
xvlog rtl/core/crypto/transform_for_key_exp.v
xvlog rtl/core/crypto/one_round_for_encdec.v
xvlog rtl/core/crypto/one_round_for_key_exp.v
xvlog rtl/core/crypto/key_expansion.v
xvlog rtl/core/crypto/sm4_encdec.v
xvlog rtl/core/crypto/sm4_top.v

# 编译包装模块
xvlog -sv rtl/core/crypto/crypto_core.sv
xvlog -sv rtl/core/crypto/crypto_engine.sv

# 编译testbench
xvlog -sv tb/tb_crypto_engine.sv

# Elaborate
xelab -debug typical tb_crypto_engine -s crypto_sim

# Run simulation
xsim crypto_sim -runall -log crypto_sim.log

echo "仿真完成，查看 crypto_sim.log"
