# 完整编译脚本 - 自动编译所有RTL模块
# 用于系统性验证所有功能

# 设置项目目录
cd D:/FPGAhanjia/Hetero_SoC_2026

# 创建工作库
vlib work

# ============================================================================
# Phase 1: Protocol & Bus Foundation
# ============================================================================
echo "=========================================="
echo "Phase 1: Protocol & Bus Foundation"
echo "=========================================="

# Package
xvlog -sv rtl/inc/pkg_axi_stream.sv

# Core modules
xvlog -sv rtl/core/axil_csr.sv
xvlog -sv rtl/core/async_fifo.sv
xvlog -sv rtl/core/gearbox_128_to_32.sv

# DMA
xvlog -sv rtl/core/dma/dma_master_engine.sv
xvlog -sv rtl/core/dma/dma_desc_fetcher.sv
xvlog -sv rtl/core/dma/dma_s2mm_mm2s_engine.sv

# PBM
xvlog -sv rtl/core/pbm/pbm_controller.sv

# ============================================================================
# Phase 2: Crypto Engine
# ============================================================================
echo "=========================================="
echo "Phase 2: Crypto Engine"
echo "=========================================="

# AES modules
xvlog rtl/core/crypto/aes_core.v
xvlog rtl/core/crypto/aes_encipher_block.v
xvlog rtl/core/crypto/aes_decipher_block.v
xvlog rtl/core/crypto/aes_sbox.v
xvlog rtl/core/crypto/aes_inv_sbox.v
xvlog rtl/core/crypto/aes_key_mem.v

# SM4 modules
xvlog rtl/core/crypto/sm4_top.v
xvlog rtl/core/crypto/sm4_encdec.v
xvlog rtl/core/crypto/key_expansion.v
xvlog rtl/core/crypto/get_cki.v
xvlog rtl/core/crypto/one_round_for_encdec.v
xvlog rtl/core/crypto/one_round_for_key_exp.v
xvlog rtl/core/crypto/sbox_replace.v
xvlog rtl/core/crypto/transform_for_encdec.v
xvlog rtl/core/crypto/transform_for_key_exp.v

# Crypto wrapper
xvlog -sv rtl/core/crypto/crypto_core.sv
xvlog -sv rtl/core/crypto/crypto_engine.sv

# ============================================================================
# Phase 3: SmartNIC Subsystem
# ============================================================================
echo "=========================================="
echo "Phase 3: SmartNIC Subsystem"
echo "=========================================="

# Parser
xvlog -sv rtl/core/parser/rx_parser.sv
xvlog -sv rtl/core/parser/arp_responder.sv

# TX
xvlog -sv rtl/core/tx/tx_stack.sv

# Flow control
xvlog -sv rtl/flow/credit_manager.sv

# Top
xvlog -sv rtl/top/packet_dispatcher.sv

# ============================================================================
# Phase 4: Advanced Features
# ============================================================================
echo "=========================================="
echo "Phase 4: Advanced Features"
echo "=========================================="

# Security
xvlog -sv rtl/security/key_vault.sv
xvlog -sv rtl/security/config_packet_auth.sv
xvlog -sv rtl/security/acl_match_engine.sv
xvlog -sv rtl/security/five_tuple_extractor.sv

# FastPath
xvlog -sv rtl/core/fast_path.sv

echo "=========================================="
echo "编译完成"
echo "=========================================="
