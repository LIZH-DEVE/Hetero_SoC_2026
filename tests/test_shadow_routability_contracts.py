import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
SHADOW_CTRL_CSR = REPO_ROOT / "rtl" / "top" / "udp_gateway_shadow_ctrl_csr.sv"
ACL_MATCH_ENGINE = REPO_ROOT / "rtl" / "security" / "acl_match_engine.sv"
WRAPPER = REPO_ROOT / "rtl" / "top" / "dma_gateway_hybrid_board_wrapper.v"


class TestShadowRoutabilityContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.shadow_ctrl_csr = SHADOW_CTRL_CSR.read_text(encoding="ascii")
        cls.acl_match_engine = ACL_MATCH_ENGINE.read_text(encoding="ascii")
        cls.wrapper = WRAPPER.read_text(encoding="ascii")

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
            "rd_gen0_q <= gen_way0[lookup_addr_q];",
            "rd_gen1_q <= gen_way1[lookup_addr_q];",
        ):
            self.assertIn(token, text)

        self.assertIn(
            "Keep the BRAM-facing lookup pipeline synchronous",
            text,
        )

    def test_wrapper_fastpath_uses_payload_bram_and_prefetched_read_data(self):
        text = self.wrapper

        for token in (
            '(* RAM_STYLE = "BLOCK" *) reg [31:0] txcap_payload_mem',
            "reg  [31:0]           txcap_read_data_q;",
            "assign txcap_data               = (SHADOW_INJECT_ONLY != 0) ? txcap_read_data_q : stage1_txcap_data;",
            "txcap_payload_mem[txcap_payload_wr_ptr_q] <= aclf_tdata;",
        ):
            self.assertIn(token, text)

        self.assertNotIn("txcap_data_mem", text)


if __name__ == "__main__":
    unittest.main()
