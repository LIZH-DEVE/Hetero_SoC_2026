# Synthesize crypto_bridge_top Out-Of-Context (OOC) to check LUT usage
create_project -force synth_crypto_bridge ./synth_crypto_bridge -part xc7z020clg400-1
set_property board_part xilinx.com:zc702:part0:1.4 [current_project]

add_files {../rtl/inc/sync_fifo.sv ../rtl/core/gearbox_128_to_32.sv ../rtl/core/crypto/crypto_bridge_top.sv ../rtl/core/crypto/aes_core.v ../rtl/core/crypto/aes_decipher_block.v ../rtl/core/crypto/aes_encipher_block.v ../rtl/core/crypto/aes_inv_sbox.v ../rtl/core/crypto/aes_key_mem.v ../rtl/core/crypto/aes_sbox.v ../rtl/core/crypto/sm4_encdec.v ../rtl/core/crypto/sm4_top.v ../rtl/core/crypto/key_expansion.v ../rtl/core/crypto/one_round_for_encdec.v ../rtl/core/crypto/one_round_for_key_exp.v ../rtl/core/crypto/sbox_replace.v ../rtl/core/crypto/transform_for_encdec.v ../rtl/core/crypto/transform_for_key_exp.v ../rtl/core/crypto/get_cki.v ../rtl/top/dma_subsystem.sv ../rtl/core/axil_csr.sv ../rtl/core/dma/dma_desc_fetcher.sv ../rtl/core/dma/dma_master_engine.sv ../rtl/core/dma/dma_s2mm_mm2s_engine.sv ../rtl/core/pbm/pbm_controller.sv ../rtl/security/acl_match_engine.sv ../rtl/security/acl_packet_filter.sv ../rtl/security/config_packet_auth.sv ../rtl/security/key_vault.sv}
set_property top dma_subsystem [current_fileset]

synth_design -mode out_of_context -top dma_subsystem

report_utilization -file crypto_bridge_utilization.rpt
report_timing_summary -file crypto_bridge_timing.rpt
exit
