import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
SHADOW_CTRL_CSR = REPO_ROOT / "rtl" / "top" / "udp_gateway_shadow_ctrl_csr.sv"
ACL_MATCH_ENGINE = REPO_ROOT / "rtl" / "security" / "acl_match_engine.sv"
PBM_CONTROLLER = REPO_ROOT / "rtl" / "core" / "pbm" / "pbm_controller.sv"
WRAPPER = REPO_ROOT / "rtl" / "top" / "dma_gateway_hybrid_board_wrapper.v"
SHADOW_PHASEC_XDC = REPO_ROOT / "constraints" / "shadow_mirror_phasec_constraints.xdc"


class TestShadowRoutabilityContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.shadow_ctrl_csr = SHADOW_CTRL_CSR.read_text(encoding="ascii")
        cls.acl_match_engine = ACL_MATCH_ENGINE.read_text(encoding="ascii")
        cls.pbm_controller = PBM_CONTROLLER.read_text(encoding="ascii")
        cls.wrapper = WRAPPER.read_text(encoding="ascii")
        cls.shadow_phasec_xdc = SHADOW_PHASEC_XDC.read_text(encoding="ascii")

    def test_shadow_ctrl_csr_uses_sync_shadow_regs_for_acl_bram_drive(self):
        text = self.shadow_ctrl_csr

        for token in (
            "always_ff @(posedge clk) begin",
            "reg_acl_addr <= 32'd0;",
            "reg_acl_data0 <= 32'd0;",
            "reg_acl_data1 <= 32'd0;",
            "reg_acl_data2 <= 32'd0;",
            "reg_acl_data3 <= 32'd0;",
            "always_comb begin",
            "acl_data3_effective = reg_acl_data3;",
            "acl_data3_effective = apply_wstrb(reg_acl_data3, s_axil_wdata, s_axil_wstrb);",
            "8'h60: reg_acl_addr <= apply_wstrb(reg_acl_addr, s_axil_wdata, s_axil_wstrb);",
            "8'h64: reg_acl_data0 <= apply_wstrb(reg_acl_data0, s_axil_wdata, s_axil_wstrb);",
            "8'h68: reg_acl_data1 <= apply_wstrb(reg_acl_data1, s_axil_wdata, s_axil_wstrb);",
            "8'h6C: reg_acl_data2 <= apply_wstrb(reg_acl_data2, s_axil_wdata, s_axil_wstrb);",
            "8'h70: begin",
            "assign o_acl_write_addr = reg_acl_addr[11:0];",
            "assign o_acl_write_data = {acl_data3_effective[7:0], reg_acl_data2, reg_acl_data1, reg_acl_data0};",
        ):
            self.assertIn(token, text)

        self.assertIn(
            "Keep ACL BRAM-facing write address/data/control on synchronous reset",
            text,
        )
        self.assertNotIn(
            "always_ff @(posedge clk or negedge rst_n) begin\n        if (!rst_n) begin\n            reg_acl_addr",
            text,
        )

    def test_acl_match_engine_uses_sync_lookup_addr_shadow_for_bram_read_port(self):
        text = self.acl_match_engine

        for token in (
            "always_ff @(posedge clk) begin",
            "lookup_addr_q  <= tuple_hash_now[ADDR_WIDTH-1:0];",
            "rd_way0_q <= bram_way0[lookup_addr_q];",
            "rd_way1_q <= bram_way1[lookup_addr_q];",
            "xpm_memory_tdpram #(",
            '.MEMORY_PRIMITIVE("block")',
            ".READ_DATA_WIDTH_A(GEN_WIDTH)",
            ".WRITE_DATA_WIDTH_B(GEN_WIDTH)",
            ".addra(lookup_addr_q)",
            ".ena(lookup_req_q)",
            ".douta(rd_gen0_q)",
            ".douta(rd_gen1_q)",
        ):
            self.assertIn(token, text)

        self.assertIn(
            "Keep the BRAM-facing lookup pipeline synchronous",
            text,
        )
        for stale_token in (
            "rd_gen0_q <= gen_way0[lookup_addr_q];",
            "rd_gen1_q <= gen_way1[lookup_addr_q];",
            "if (gen_way0[acl_write_addr] != active_gen) begin",
            "end else if (gen_way1[acl_write_addr] != active_gen) begin",
        ):
            self.assertNotIn(stale_token, text)

    def test_wrapper_fastpath_uses_payload_bram_and_prefetched_read_data(self):
        text = self.wrapper

        for token in (
            "xpm_memory_sdpram #(",
            '.MEMORY_PRIMITIVE("block")',
            ".WRITE_DATA_WIDTH_A(DATA_WIDTH)",
            ".READ_DATA_WIDTH_B(DATA_WIDTH)",
            "reg                   txcap_payload_rd_pending_q;",
            "if (txcap_payload_rd_pending_q) begin",
            ".doutb(txcap_payload_rd_data)",
            "reg  [31:0]           txcap_read_data_q;",
            "assign txcap_data               = (SHADOW_INJECT_ONLY != 0) ? txcap_read_data_q : stage1_txcap_data;",
        ):
            self.assertIn(token, text)

        for stale_token in (
            '(* RAM_STYLE = "BLOCK" *) reg [31:0] txcap_payload_mem',
            "txcap_payload_mem[txcap_payload_wr_ptr_q] <= aclf_tdata;",
            "txcap_read_data_q <= txcap_payload_mem[(txcap_rd_ptr_q + 9'd1) - FASTPATH_HDR_WORDS];",
        ):
            self.assertNotIn(stale_token, text)

    def test_pbm_controller_uses_explicit_block_bram_xpm(self):
        text = self.pbm_controller
        for token in (
            "xpm_memory_sdpram #(",
            '.MEMORY_PRIMITIVE("block")',
            ".WRITE_DATA_WIDTH_A(DATA_WIDTH)",
            ".READ_DATA_WIDTH_B(DATA_WIDTH)",
            ".ADDR_WIDTH_A(PBM_WORD_ADDR_WIDTH)",
            ".ADDR_WIDTH_B(PBM_WORD_ADDR_WIDTH)",
            '(* DONT_TOUCH = "true", KEEP = "true" *) logic                      pbm_wr_cmd_q;',
            '(* DONT_TOUCH = "true", KEEP = "true" *) logic [0:0]                pbm_wr_wea_q;',
            '(* DONT_TOUCH = "true", KEEP = "true" *) logic [PBM_WORD_ADDR_WIDTH-1:0] pbm_wr_addr_q;',
            '(* DONT_TOUCH = "true", KEEP = "true" *) logic [DATA_WIDTH-1:0]     pbm_wr_data_q;',
            "if (!rst_n) begin",
            "pbm_wr_cmd_q <= 1'b0;",
            "pbm_wr_wea_q <= '0;",
            "pbm_wr_addr_q <= '0;",
            "pbm_wr_data_q <= '0;",
            "pbm_wr_cmd_q <= pbm_wr_en;",
            "pbm_wr_wea_q <= {pbm_wr_en};",
            "if (pbm_wr_en) begin",
            "pbm_wr_addr_q <= pbm_wr_addr;",
            "pbm_wr_data_q <= i_wr_data;",
            ".ena(pbm_wr_cmd_q)",
            ".wea(pbm_wr_wea_q)",
            ".addra(pbm_wr_addr_q)",
            ".dina(pbm_wr_data_q)",
        ):
            self.assertIn(token, text)

        self.assertNotIn(
            '(* ram_style = "block" *) logic [DATA_WIDTH-1:0] ram [0:DEPTH-1];',
            text,
        )
        self.assertNotIn(".ena(pbm_wr_en)", text)
        self.assertNotIn(".wea(pbm_wr_wea)", text)
        self.assertNotIn(".addra(pbm_wr_addr)", text)
        self.assertNotIn(".dina(i_wr_data)", text)

    def test_acl_match_engine_forces_generation_tables_into_block_ram(self):
        text = self.acl_match_engine
        for token in (
            "logic                  acl_wr_stage_valid;",
            "logic                  acl_wr_queue_valid;",
            "acl_wr_gen0_q, acl_wr_gen1_q;",
            "assign acl_wr_way0_free = (acl_wr_gen0_q != active_gen);",
            "assign acl_wr_way1_free = (acl_wr_gen1_q != active_gen);",
        ):
            self.assertIn(token, text)

        self.assertNotIn(
            '(* RAM_STYLE = "BLOCK" *) logic [GEN_WIDTH-1:0] gen_way0 [0:DEPTH-1];',
            text,
        )
        self.assertNotIn(
            '(* RAM_STYLE = "BLOCK" *) logic [GEN_WIDTH-1:0] gen_way1 [0:DEPTH-1];',
            text,
        )

    def test_shadow_data_region_merges_live_crypto_without_shadow_ctrl_overlap(self):
        text = self.shadow_phasec_xdc

        self.assertNotIn("create_pblock live_crypto_region", text)
        self.assertIn("create_pblock shadow_data_region", text)
        self.assertIn("udp_gateway_shadow_mirror_i/crypto_accel_axi_0/inst", text)
        self.assertIn("SLICE_X0Y0:SLICE_X113Y49", text)
        self.assertIn("SLICE_X26Y50:SLICE_X95Y98", text)
        self.assertIn("SLICE_X0Y100:SLICE_X95Y149", text)
        self.assertIn("SLICE_X96Y50:SLICE_X113Y98", text)
        self.assertNotIn("SLICE_X80Y51:SLICE_X95Y98", text)
        self.assertNotIn("SLICE_X26Y50:SLICE_X79Y98", text)
        self.assertNotIn("SLICE_X0Y100:SLICE_X113Y149", text)
        self.assertNotIn("set_property IS_SOFT TRUE [get_pblocks live_crypto_region]", text)


if __name__ == "__main__":
    unittest.main()
