import pathlib
import re
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
RTL = REPO_ROOT / "rtl"
HCS_SOC = REPO_ROOT / "HCS_SOC"
LEGACY_ROOT = HCS_SOC / "legacy"
LEGACY_APPS = LEGACY_ROOT / "apps"
LEGACY_SCRIPTS = LEGACY_ROOT / "scripts"
TB = REPO_ROOT / "tb"

CLASSIFIER_SV = RTL / "core" / "dma" / "udp_dma_ingress_classifier.sv"
WRAPPER_SV = RTL / "top" / "dma_gateway_hybrid_board_wrapper.v"
EXPORT_TCL = LEGACY_SCRIPTS / "export_dma_gateway_hybrid_xsa.tcl"
EXPORT_PS1 = LEGACY_SCRIPTS / "export_dma_gateway_hybrid_xsa.ps1"
BENCH_SV = TB / "tb_dma_gateway_hybrid_board_wrapper.sv"
RING_DRIVER_C = HCS_SOC / "dma_mvp_ps_driver_ref.c"
DMA_HW_REGS_H = HCS_SOC / "dma_hw_regs.h"
PROOF_APP_C = LEGACY_APPS / "ax7020_dma_gateway_hybrid_perf_proof_app" / "src" / "main.c"
CRYPTO_DMA_SUBSYSTEM_SV = RTL / "top" / "crypto_dma_subsystem.sv"
SOURCE_READER_SV = RTL / "core" / "dma" / "dma_crypto_source_reader.sv"
DMA_MASTER_ENGINE_SV = RTL / "core" / "dma" / "dma_master_engine.sv"
TB_RING_WRITEBACK_SV = TB / "tb_dma_ring_ps_bfm_writeback.sv"
TB_FULL_SYSTEM_SV = TB / "tb_full_system_verification.sv"
DMA_CSR_PKG_SV = RTL / "inc" / "dma_csr_pkg.sv"
SHADOW_INJECT_SV = RTL / "top" / "udp_gateway_shadow_inject_path.sv"
CRYPTO_BRIDGE_SV = RTL / "core" / "crypto" / "crypto_bridge_top.sv"
CRYPTO_AXI_S00_SV = RTL / "core" / "crypto_axi" / "crypto_accel_axi_slave_lite_v1_0_S00_AXI.v"


class TestDmaGatewayHybridContracts(unittest.TestCase):
    def test_stage1_inject_fifo_can_hold_exact_fit_smoke_frame(self):
        text = (RTL / "top" / "network_stage1_path.sv").read_text(encoding="ascii")

        match = re.search(r"localparam int INJ_DEPTH = (\d+);", text)
        self.assertIsNotNone(match, "network_stage1_path must declare INJ_DEPTH")

        inj_depth = int(match.group(1))
        exact_fit_frame_words = 11 + (1024 // 4)
        self.assertGreaterEqual(
            inj_depth,
            exact_fit_frame_words,
            "stage1 inject FIFO must hold the full exact-fit hybrid smoke frame",
        )

        for token in (
            "localparam int INJ_PTR_W = $clog2(INJ_DEPTH);",
            "localparam int INJ_COUNT_W = $clog2(INJ_DEPTH + 1);",
            "logic [INJ_PTR_W-1:0]  inj_wr_ptr;",
            "logic [INJ_PTR_W-1:0]  inj_rd_ptr;",
            "logic [INJ_COUNT_W-1:0] inj_count;",
            "inj_wr_ptr <= inj_wr_ptr + INJ_PTR_W'(1);",
            "inj_rd_ptr <= inj_rd_ptr + INJ_PTR_W'(1);",
            "inj_count <= inj_count + INJ_COUNT_W'(1);",
            "inj_count <= inj_count - INJ_COUNT_W'(1);",
        ):
            self.assertIn(token, text)

    def test_classifier_enforces_wrong_port_and_unaligned_drop_contracts(self):
        text = CLASSIFIER_SV.read_text(encoding="ascii")

        for token in (
            "module udp_dma_ingress_classifier",
            "16'd4660",
            "16'd4661",
            "o_drop_wrong_port_count",
            "o_drop_unaligned_count",
            "o_dma_idle",
            "m_axis_dma_tvalid",
            "must be consumed to TLAST",
            "wrong-port frames must never drive DMA tvalid",
            "unaligned frames must never drive DMA tvalid",
            "drop_wrong_port_frame",
            "drop_unaligned_frame",
            "m_axis_dma_terror",
            "payload_bytes_remaining_q",
            "length_error_q",
            "length_error_now",
            "udp_payload_bytes_now",
            "payload_bytes_remaining_q <= udp_payload_bytes_now;",
            "length_error_q <= 1'b1;",
        ):
            self.assertIn(token, text)

        self.assertIn("assign o_dma_idle = !m_axis_dma_tvalid;", text)
        self.assertIn(
            "assign m_axis_dma_terror = s_axis_tvalid && accept_frame_q && (state_q == STATE_PAYLOAD) && s_axis_tlast && (length_error_q || length_error_now);",
            text,
        )

    def test_hybrid_wrapper_uses_stage1_classifier_and_crypto_dma_windows(self):
        text = WRAPPER_SV.read_text(encoding="ascii")

        for token in (
            "module dma_gateway_hybrid_board_wrapper",
            "localparam [7:0] WRAP_REG_DROP_WRONG_PORT_COUNT = 8'hCC;",
            "localparam [7:0] WRAP_REG_DROP_UNALIGNED_COUNT = 8'hD0;",
            "axil_csr",
            "network_stage1_path",
            "udp_dma_ingress_classifier",
            "crypto_dma_subsystem",
            ".o_drop_wrong_port_count(drop_wrong_port_count)",
            ".o_drop_unaligned_count(drop_unaligned_count)",
            ".i_drop_wrong_port_count(drop_wrong_port_count)",
            ".i_drop_unaligned_count(drop_unaligned_count)",
            ".o_inject_tdata(stage1_inject_tdata)",
            ".rx_wr_data(classifier_dma_tdata)",
            ".rx_wr_valid(classifier_dma_tvalid)",
            ".rx_wr_last(classifier_dma_tlast)",
            ".rx_wr_error(classifier_dma_terror)",
            ".rx_wr_ready(classifier_dma_tready)",
            ".m_axis_awaddr(m_axi_dma_wr_awaddr)",
            ".m_axis_s2mm_awaddr(m_axi_s2mm_awaddr)",
            "output wire [31:0]             o_tx_axis_tdata,",
            "output wire                    o_tx_axis_tvalid,",
            "output wire                    o_tx_axis_tlast,",
            "output wire [3:0]              o_tx_axis_tkeep,",
            "input  wire                    i_tx_axis_tready",
            "wire [31:0]           subsys_tx_axis_tdata;",
            "wire                  subsys_tx_axis_tvalid;",
            "wire                  subsys_tx_axis_tlast;",
            "wire [3:0]            subsys_tx_axis_tkeep;",
            "wire                  subsys_tx_axis_tready;",
            ".tx_axis_tdata(subsys_tx_axis_tdata)",
            ".tx_axis_tvalid(subsys_tx_axis_tvalid)",
            ".tx_axis_tlast(subsys_tx_axis_tlast)",
            ".tx_axis_tkeep(subsys_tx_axis_tkeep)",
            ".tx_axis_tready(subsys_tx_axis_tready)",
        ):
            self.assertIn(token, text)
        self.assertNotIn("dma_raw_copy_subsystem", text)

    def test_shadow_inject_only_wrapper_exposes_live_netdbg_and_diag_clear_hooks(self):
        text = WRAPPER_SV.read_text(encoding="ascii")

        for token in (
            "wire [31:0]           shadow_netdbg_status;",
            "reg                   shadow_dbg_stage1_fire_seen_q;",
            "reg                   shadow_dbg_acl_fire_seen_q;",
            "reg                   shadow_dbg_classifier_in_fire_seen_q;",
            "reg                   shadow_dbg_classifier_dma_valid_seen_q;",
            "reg                   shadow_dbg_classifier_dma_fire_seen_q;",
            "reg                   shadow_dbg_classifier_dma_ready_seen_q;",
            "assign netdbg_status            = (SHADOW_INJECT_ONLY != 0) ? shadow_netdbg_status : stage1_netdbg_status;",
            ".i_diag_clear(inj_clear)",
        ):
            self.assertIn(token, text)

        self.assertEqual(
            2,
            text.count(".i_diag_clear(inj_clear)"),
            "wrapper must fan out inj_clear into both ACL and classifier diag-clear ports",
        )
        self.assertNotIn(
            "assign netdbg_status            = (SHADOW_INJECT_ONLY != 0) ? 32'd0 : stage1_netdbg_status;",
            text,
        )

    def test_hybrid_wrapper_zero_copy_fastpath_muxes_wrapper_egress_over_subsystem_tx(self):
        text = WRAPPER_SV.read_text(encoding="ascii")

        for token in (
            "wire [31:0]           egress_tx_axis_tdata;",
            "wire                  egress_tx_axis_tvalid;",
            "wire                  egress_tx_axis_tlast;",
            "wire [3:0]            egress_tx_axis_tkeep;",
            "wire                  fastpath_egress_selected;",
            "assign subsys_tx_axis_tready = fastpath_egress_selected ? 1'b0 : i_tx_axis_tready;",
            "assign o_tx_axis_tdata = fastpath_egress_selected ? egress_tx_axis_tdata : subsys_tx_axis_tdata;",
            "assign o_tx_axis_tvalid = fastpath_egress_selected ? egress_tx_axis_tvalid : subsys_tx_axis_tvalid;",
            "assign o_tx_axis_tlast = fastpath_egress_selected ? egress_tx_axis_tlast : subsys_tx_axis_tlast;",
            "assign o_tx_axis_tkeep = fastpath_egress_selected ? egress_tx_axis_tkeep : subsys_tx_axis_tkeep;",
        ):
            self.assertIn(token, text)

    def test_export_chain_clones_design1_into_hybrid_wrapper_with_dual_windows(self):
        tcl = EXPORT_TCL.read_text(encoding="ascii")
        ps1 = EXPORT_PS1.read_text(encoding="ascii")

        for token in (
            'set raw_bd_name "dma_gateway_hybrid"',
            '{"rtl/core/dma/dma_crypto_source_reader.sv" "SystemVerilog"}',
            '{"rtl/core/dma/dma_master_engine.sv" "SystemVerilog"}',
            '{"rtl/top/crypto_dma_subsystem.sv" "SystemVerilog"}',
            "dma_gateway_hybrid_board_wrapper",
            "create_bd_cell -type module -reference dma_gateway_hybrid_board_wrapper dma_gateway_hybrid_0",
            "set_property -dict [list CONFIG.NUM_MI {2}] [get_bd_cells ps7_0_axi_periph]",
            "connect_bd_intf_net [get_bd_intf_pins dma_gateway_hybrid_0/s_axil_ctrl] [get_bd_intf_pins ps7_0_axi_periph/M00_AXI]",
            "connect_bd_intf_net [get_bd_intf_pins dma_gateway_hybrid_0/s_axil_dma] [get_bd_intf_pins ps7_0_axi_periph/M01_AXI]",
            "dma_gateway_hybrid_wrapper.xsa",
        ):
            self.assertIn(token, tcl)

        self.assertRegex(
            tcl,
            r"assign_bd_address -offset 0x40000000 -range 4K[\s\\\n]+"
            r"-target_address_space \[get_bd_addr_spaces processing_system7_0/Data\][\s\\\n]+"
            r"\[get_bd_addr_segs dma_gateway_hybrid_0/s_axil_ctrl/reg0\] -force",
        )
        self.assertRegex(
            tcl,
            r"assign_bd_address -offset 0x40001000 -range 4K[\s\\\n]+"
            r"-target_address_space \[get_bd_addr_spaces processing_system7_0/Data\][\s\\\n]+"
            r"\[get_bd_addr_segs dma_gateway_hybrid_0/s_axil_dma/reg0\] -force",
        )

        self.assertIn("export_dma_gateway_hybrid_xsa.tcl", ps1)
        self.assertIn("dma_gateway_hybrid_wrapper.xsa", ps1)

    def test_bench_covers_wrong_port_idle_and_unaligned_drop(self):
        text = BENCH_SV.read_text(encoding="ascii")

        for token in (
            "module tb_dma_gateway_hybrid_board_wrapper",
            "WRONG_PORT PASS",
            "UNALIGNED_REJECT PASS",
            "drop_wrong_port_count",
            "drop_unaligned_count",
            "DMA ingress must remain idle while wrong-port frame is drained",
            "wrong-port frame changed ring pointers",
            "wrong-port frame triggered completion",
            "unaligned frame defensive drop did not increment counter",
        ):
            self.assertIn(token, text)

    def test_ps_ring_driver_writes_crypto_src_addr_for_descriptor_driven_source_path(self):
        text = RING_DRIVER_C.read_text(encoding="ascii")

        for token in (
            "desc->src_addr = raw_copy_mode ? src_addr : ((payload_addr != 0) ? (uint32_t)(uintptr_t)payload_addr : 0u);",
            "if (!stream_mode && ((uint32_t)(uintptr_t)payload_addr & (DMA_ALIGNMENT_BYTES - 1u)) != 0u) {",
            "return -6;",
        ):
            self.assertIn(token, text)

    def test_proof_timeout_and_descriptor_error_paths_report_ring_diagnostics(self):
        text = PROOF_APP_C.read_text(encoding="ascii")

        for token in (
            "diag.last_descriptor_poll_count = poll_count;",
            "PROOF_TIMEOUT_DIAG algo=%s length=%u",
            "PROOF_DESC_ERR_DIAG algo=%s length=%u poll_rc=%d",
            "diag.descriptor_error_count = 1u;",
            "poll_rc == -1",
            "if (poll_rc < 0)",
            "DMA_CSR_RING_HW_HEAD",
            "DMA_CSR_RING_SW_TAIL",
            "DMA_CSR_STATUS",
            "dma_ring_irq_status(ctx)",
            "PROOF_ADDR ring=0x%08x src=0x%08x dst0=0x%08x",
        ):
            self.assertIn(token, text)

    def test_stage2_debug_csr_contracts_are_exposed_end_to_end(self):
        regs = DMA_HW_REGS_H.read_text(encoding="ascii")
        app = PROOF_APP_C.read_text(encoding="ascii")
        subsystem = CRYPTO_DMA_SUBSYSTEM_SV.read_text(encoding="ascii")
        source_reader = SOURCE_READER_SV.read_text(encoding="ascii")
        sink = DMA_MASTER_ENGINE_SV.read_text(encoding="ascii")

        for token in (
            "DMA_CSR_DEBUG_STATUS",
            "DMA_CSR_DEBUG_SOURCE_PROGRESS",
            "DMA_CSR_DEBUG_SINK_PROGRESS",
            "DMA_CSR_DEBUG_PLAINTEXT_WORD0",
            "DMA_CSR_DEBUG_PLAINTEXT_WORD1",
            "DMA_CSR_DEBUG_PLAINTEXT_WORD2",
            "DMA_CSR_DEBUG_PLAINTEXT_WORD3",
            "DMA_CSR_DEBUG_KEY_WORD0",
            "DMA_CSR_DEBUG_KEY_WORD1",
            "DMA_CSR_DEBUG_KEY_WORD2",
            "DMA_CSR_DEBUG_KEY_WORD3",
        ):
            self.assertIn(token, regs)

        for token in (
            "dbg_status=0x%08x",
            "dbg_src=0x%08x",
            "dbg_sink=0x%08x",
            "hybrid_dma_read32(DMA_CSR_DEBUG_STATUS)",
            "hybrid_dma_read32(DMA_CSR_DEBUG_SOURCE_PROGRESS)",
            "hybrid_dma_read32(DMA_CSR_DEBUG_SINK_PROGRESS)",
            "PROOF_HW_BLOCK%08x%08x%08x%08x",
            "PROOF_HW_KEY%08x%08x%08x%08x",
            "hybrid_dma_read32(DMA_CSR_DEBUG_PLAINTEXT_WORD0)",
            "hybrid_dma_read32(DMA_CSR_DEBUG_KEY_WORD0)",
        ):
            self.assertIn(token, app)

        for token in (
            "csr_debug_status",
            "csr_debug_source_progress",
            "csr_debug_sink_progress",
            "bridge_debug_last_plaintext",
            "bridge_debug_key_lo_active",
            ".i_debug_status(csr_debug_status)",
            ".i_debug_source_progress(csr_debug_source_progress)",
            ".i_debug_sink_progress(csr_debug_sink_progress)",
            ".i_debug_plaintext_word0(bridge_debug_last_plaintext[127:96])",
            ".i_debug_key_word0(bridge_debug_key_lo_active[127:96])",
            "source_last_rresp",
            "source_bytes_fetched",
            "sink_bytes_written",
            "parameter CRYPTO_NUM_INSTANCES = 1",
            ".NUM_INSTANCES(CRYPTO_NUM_INSTANCES)",
        ):
            self.assertIn(token, subsystem)

        bridge = (RTL / "core" / "crypto" / "crypto_bridge_top.sv").read_text(encoding="utf-8", errors="ignore")
        for token in (
            "o_debug_last_plaintext",
            "o_debug_key_lo_active",
            "debug_last_plaintext_q",
            "assign o_debug_last_plaintext = debug_last_plaintext_q;",
            "assign o_debug_key_lo_active = key_lo_active;",
            "debug_last_plaintext_q <= plaintext_reg;",
        ):
            self.assertIn(token, bridge)

        for token in (
            "o_debug_last_rresp",
            "o_debug_bytes_fetched",
            "o_debug_bytes_delivered",
            "o_debug_state",
            "function automatic [DATA_WIDTH-1:0] pbm_word_order",
            "pbm_word_order = {value[7:0], value[15:8], value[23:16], value[31:24]};",
            "logic [DATA_WIDTH-1:0]   rd_data_q;",
            "logic                    rd_valid_q;",
            "assign o_rd_data = rd_data_q;",
            "assign o_rd_valid = rd_valid_q;",
            "rd_data_q <= pbm_word_order(fifo_m_tdata);",
            "rd_valid_q <= 1'b1;",
        ):
            self.assertIn(token, source_reader)

    def test_shadow_merge_uses_single_crypto_instance_contract(self):
        wrapper = WRAPPER_SV.read_text(encoding="ascii")
        subsystem = CRYPTO_DMA_SUBSYSTEM_SV.read_text(encoding="ascii")
        crypto_axi = CRYPTO_AXI_S00_SV.read_text(encoding="utf-8", errors="ignore")

        self.assertIn("parameter CRYPTO_NUM_INSTANCES = 1", subsystem)
        self.assertIn(".CRYPTO_NUM_INSTANCES(CRYPTO_NUM_INSTANCES)", wrapper)
        self.assertIn(".NUM_INSTANCES(1)", crypto_axi)

    def test_shadow_merge_fifo_depths_are_slimmed_for_fit(self):
        dma_pkg = DMA_CSR_PKG_SV.read_text(encoding="ascii")
        inject = SHADOW_INJECT_SV.read_text(encoding="ascii")
        bridge = CRYPTO_BRIDGE_SV.read_text(encoding="utf-8", errors="ignore")

        self.assertIn("localparam int unsigned DMA_RAW_COPY_FIFO_DEPTH = 32;", dma_pkg)
        self.assertIn("localparam int INJ_DEPTH = 32;", inject)
        self.assertIn("sync_fifo #(.WIDTH(128), .DEPTH(16)) u_mid_fifo (", bridge)
        self.assertIn("sync_fifo #(.WIDTH(33), .DEPTH(16)) u_out_fifo (", bridge)

    def test_dma_master_engine_tracks_debug_written_bytes(self):
        text = DMA_MASTER_ENGINE_SV.read_text(encoding="ascii")

        for token in (
            "localparam int unsigned BYTES_PER_BEAT = DATA_WIDTH / 8;",
            "logic [31:0]             bytes_written_q;",
            "bytes_written_q <= 32'd0;",
            "bytes_written_q <= bytes_written_q + BYTES_PER_BEAT;",
            "assign o_debug_bytes_written = bytes_written_q;",
        ):
            self.assertIn(token, text)

    def test_dma_master_engine_rejects_unaligned_total_length_instead_of_truncating(self):
        text = DMA_MASTER_ENGINE_SV.read_text(encoding="ascii")

        for token in (
            "logic                    len_unaligned;",
            "assign len_unaligned = (i_total_len[1:0] != 2'b00);",
            "if (i_start && (addr_unaligned || len_unaligned)) begin",
            "if (i_start && i_total_len != 0 && !addr_unaligned && !len_unaligned) begin",
            "else if (i_start && i_total_len != 0 && !addr_unaligned && !len_unaligned) begin",
        ):
            self.assertIn(token, text)

        self.assertNotIn("bytes_remaining <= {i_total_len[31:2], 2'b00};", text)

    def test_dma_master_engine_outstanding_limit_matches_active_axi_contract(self):
        text = DMA_MASTER_ENGINE_SV.read_text(encoding="ascii")

        self.assertIn("parameter integer MAX_OUTSTANDING_WRITES = 1", text)
        self.assertIn(
            "assign aw_issue_allowed = (outstanding_writes < MAX_OUTSTANDING_WRITES);",
            text,
        )

    def test_testbenches_tie_new_debug_csr_ports_low(self):
        ring_tb = TB_RING_WRITEBACK_SV.read_text(encoding="ascii")
        full_tb = TB_FULL_SYSTEM_SV.read_text(encoding="utf-8", errors="ignore")

        for token in (
            ".i_debug_status",
            ".i_debug_source_progress",
            ".i_debug_sink_progress",
        ):
            self.assertIn(token, ring_tb)
            self.assertIn(token, full_tb)

    def test_proof_app_writes_key_regs_in_bridge_word_order_and_invalidates_full_slot_stride(self):
        text = PROOF_APP_C.read_text(encoding="ascii")

        for token in (
            "hybrid_dma_write32(HYBRID_DMA_KEY0_REG, hybrid_load_be_word(&key[12]));",
            "hybrid_dma_write32(HYBRID_DMA_KEY1_REG, hybrid_load_be_word(&key[8]));",
            "hybrid_dma_write32(HYBRID_DMA_KEY2_REG, hybrid_load_be_word(&key[4]));",
            "hybrid_dma_write32(HYBRID_DMA_KEY3_REG, hybrid_load_be_word(&key[0]));",
            "dma_ring_invalidate_result(slot_ptr, stride);",
        ):
            self.assertIn(token, text)

        self.assertRegex(
            text,
            r"hybrid_prepare_ring\(&ctx\);\s+hybrid_configure_crypto_context\(algo\);",
            "run_hw_batch must re-arm crypto context after dma_ring_soft_reset clears DMA_CSR_CTRL",
        )

        self.assertRegex(
            text,
            r"memset\(&g_dst_region, 0xA5, sizeof\(g_dst_region\)\);\s+"
            r"Xil_DCacheFlushRange\(\(INTPTR\)g_dst_region\.payload, HYBRID_DEFAULT_BENCH_REPEATS \* stride\);",
            "run_hw_batch must flush the destination slab after A5 init so dirty cache lines do not overwrite DMA results",
        )

    def test_crypto_dma_subsystem_swaps_bridge_words_only_for_dma_sink(self):
        text = CRYPTO_DMA_SUBSYSTEM_SV.read_text(encoding="ascii")

        for token in (
            "parameter CRYPTO_NUM_INSTANCES = 1",
            "function automatic [31:0] dma_sink_word_order",
            "dma_sink_word_order = {value[7:0], value[15:8], value[23:16], value[31:24]};",
            "muxed_crypto_data = dma_sink_word_order(crypto_to_dma_data);",
            "tx_axis_tdata = 32'b0;",
            "tx_axis_tvalid = 1'b0;",
            "tx_axis_tlast = 1'b0;",
            "tx_axis_tkeep = 4'h0;",
            "tx_axis_tdata = crypto_to_dma_data;",
            "tx_axis_tvalid = !crypto_to_dma_empty;",
            "tx_axis_tlast = crypto_to_dma_last;",
            "tx_axis_tkeep = 4'hF;",
            ".NUM_INSTANCES(CRYPTO_NUM_INSTANCES)",
        ):
            self.assertIn(token, text)

        for stale_token in (
            '(* mark_debug = "true" *) logic [31:0]            tx_data_from_crypto;',
            '(* mark_debug = "true" *) logic                   tx_valid_from_crypto;',
            '(* mark_debug = "true" *) logic                   tx_last_from_crypto;',
            "assign tx_axis_tdata = tx_data_from_crypto;",
            "assign tx_axis_tvalid = tx_valid_from_crypto;",
            "assign tx_axis_tlast = tx_last_from_crypto;",
            "assign tx_axis_tkeep = 4'hF;",
        ):
            self.assertNotIn(stale_token, text)

    def test_dma_crypto_source_reader_uses_burst_reads_not_single_beat_arlen_zero(self):
        text = SOURCE_READER_SV.read_text(encoding="ascii")

        for token in (
            "logic [31:0]             burst_bytes_calc;",
            "logic [7:0]              current_arlen;",
            "logic [8:0]              beat_count;",
            "logic [12:0]             dist_to_4k;",
            "assign dist_to_4k = 13'h1000 - {1'b0, read_addr_q[11:0]};",
            "burst_bytes_calc = (bytes_remaining < limit) ? bytes_remaining : limit;",
            "current_arlen <= burst_bytes_calc[31:2] - 1;",
            "assign m_axi_arlen   = current_arlen;",
            "if (m_axi_rvalid && m_axi_rready) begin",
            "if (m_axi_rlast) begin",
        ):
            self.assertIn(token, text)

        self.assertNotIn("assign m_axi_arlen   = 8'd0;", text)


if __name__ == "__main__":
    unittest.main()
