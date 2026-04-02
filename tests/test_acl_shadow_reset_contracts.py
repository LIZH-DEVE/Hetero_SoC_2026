import pathlib
import re
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
SHADOW_CTRL_CSR = REPO_ROOT / "rtl" / "top" / "udp_gateway_shadow_ctrl_csr.sv"
ACL_MATCH_ENGINE = REPO_ROOT / "rtl" / "security" / "acl_match_engine.sv"
ACL_PACKET_FILTER = REPO_ROOT / "rtl" / "security" / "acl_packet_filter.sv"
PBM_CONTROLLER = REPO_ROOT / "rtl" / "core" / "pbm" / "pbm_controller.sv"
DMA_INGRESS_CLASSIFIER = REPO_ROOT / "rtl" / "core" / "dma" / "udp_dma_ingress_classifier.sv"
SHADOW_WRAPPER = REPO_ROOT / "rtl" / "top" / "dma_gateway_hybrid_board_wrapper.v"
SHADOW_INJECT_PATH = REPO_ROOT / "rtl" / "top" / "udp_gateway_shadow_inject_path.sv"


ALWAYS_FF_RE = re.compile(r"always_ff\s*@\((.*?)\)\s*begin")
BEGIN_END_RE = re.compile(r"\bbegin\b|\bend\b")


def _extract_always_ff_blocks(text: str) -> list[tuple[str, str]]:
    blocks: list[tuple[str, str]] = []
    for match in ALWAYS_FF_RE.finditer(text):
        sensitivity = " ".join(match.group(1).split())
        depth = 0
        for token in BEGIN_END_RE.finditer(text, match.end() - len("begin")):
            if token.group(0) == "begin":
                depth += 1
            else:
                depth -= 1
                if depth == 0:
                    blocks.append((sensitivity, text[match.start():token.end()]))
                    break
        else:
            raise AssertionError(f"Unterminated always_ff block for sensitivity list: {sensitivity}")
    return blocks


class TestAclShadowResetContracts(unittest.TestCase):
    def test_shadow_acl_write_window_moves_bram_facing_regs_out_of_async_reset(self):
        text = SHADOW_CTRL_CSR.read_text(encoding="ascii")
        blocks = _extract_always_ff_blocks(text)

        async_blocks = [block for sensitivity, block in blocks if sensitivity == "posedge clk or negedge rst_n"]
        self.assertTrue(async_blocks, "Expected at least one async-reset always_ff block in shadow CSR")
        for pattern in (
            r"reg_acl_addr\s*<=",
            r"reg_acl_data0\s*<=",
            r"reg_acl_data1\s*<=",
            r"reg_acl_data2\s*<=",
            r"reg_acl_data3\s*<=",
            r"o_acl_write_en\s*<=",
            r"o_acl_clear\s*<=",
        ):
            self.assertTrue(
                all(re.search(pattern, block) is None for block in async_blocks),
                f"{pattern} should not remain in an async-reset always_ff block",
            )

        sync_blocks = [
            block
            for sensitivity, block in blocks
            if sensitivity == "posedge clk" and re.search(r"reg_acl_addr\s*<=", block)
        ]
        self.assertEqual(1, len(sync_blocks), "Expected one dedicated sync/no-async-reset ACL write block")
        acl_block = sync_blocks[0]

        for token in (
            "if (!rst_n) begin",
            "reg_acl_addr <= 32'd0;",
            "reg_acl_data0 <= 32'd0;",
            "reg_acl_data1 <= 32'd0;",
            "reg_acl_data2 <= 32'd0;",
            "reg_acl_data3 <= 32'd0;",
            "o_acl_write_en <= 1'b0;",
            "o_acl_clear <= 1'b0;",
            "8'h60: reg_acl_addr <= apply_wstrb(reg_acl_addr, s_axil_wdata, s_axil_wstrb);",
            "8'h64: reg_acl_data0 <= apply_wstrb(reg_acl_data0, s_axil_wdata, s_axil_wstrb);",
            "8'h68: reg_acl_data1 <= apply_wstrb(reg_acl_data1, s_axil_wdata, s_axil_wstrb);",
            "8'h6C: reg_acl_data2 <= apply_wstrb(reg_acl_data2, s_axil_wdata, s_axil_wstrb);",
            "reg_acl_data3 <= apply_wstrb(reg_acl_data3, s_axil_wdata, s_axil_wstrb);",
        ):
            self.assertIn(token, acl_block)

        self.assertIn("assign o_acl_write_addr = reg_acl_addr[11:0];", text)

    def test_acl_lookup_address_pipeline_is_no_longer_async_reset(self):
        text = ACL_MATCH_ENGINE.read_text(encoding="ascii")
        blocks = _extract_always_ff_blocks(text)

        async_blocks = [block for sensitivity, block in blocks if sensitivity == "posedge clk or negedge rst_n"]
        for pattern in (
            r"lookup_addr_q\s*<=",
            r"lookup_tuple_q\s*<=",
            r"lookup_gen_q\s*<=",
            r"lookup_req_q\s*<=",
        ):
            self.assertTrue(
                all(re.search(pattern, block) is None for block in async_blocks),
                f"{pattern} should not remain in an async-reset always_ff block",
            )

        lookup_blocks = [
            block
            for sensitivity, block in blocks
            if sensitivity == "posedge clk" and re.search(r"lookup_addr_q\s*<=", block)
        ]
        self.assertEqual(1, len(lookup_blocks), "Expected one dedicated sync/no-async-reset lookup pipeline block")
        lookup_block = lookup_blocks[0]

        for token in (
            "if (!rst_n) begin",
            "lookup_addr_q  <= '0;",
            "lookup_tuple_q <= '0;",
            "lookup_gen_q   <= '0;",
            "lookup_req_q   <= 1'b0;",
            "lookup_req_q  <= tuple_valid;",
            "if (tuple_valid) begin",
            "lookup_addr_q  <= tuple_hash_now[ADDR_WIDTH-1:0];",
            "lookup_tuple_q <= tuple_in;",
            "lookup_gen_q   <= active_gen;",
        ):
            self.assertIn(token, lookup_block)

        self.assertIn("rd_way0_q <= bram_way0[lookup_addr_q];", text)
        self.assertIn("rd_way1_q <= bram_way1[lookup_addr_q];", text)

    def test_shadow_acl_runtime_state_is_no_longer_async_reset(self):
        text = ACL_MATCH_ENGINE.read_text(encoding="ascii")
        self.assertIn("always_ff @(posedge clk) begin", text)
        self.assertNotIn("always_ff @(posedge clk or negedge rst_n) begin", text)
        self.assertIn("active_gen     <= {{(GEN_WIDTH-1){1'b0}}, 1'b1};", text)

    def test_acl_packet_filter_state_is_no_longer_async_reset(self):
        text = ACL_PACKET_FILTER.read_text(encoding="ascii")
        self.assertIn("always_ff @(posedge clk) begin", text)
        self.assertNotIn("always_ff @(posedge clk or negedge rst_n) begin", text)
        self.assertIn("state <= ST_IDLE;", text)

    def test_pbm_and_classifier_state_are_no_longer_async_reset(self):
        pbm_text = PBM_CONTROLLER.read_text(encoding="ascii")
        classifier_text = DMA_INGRESS_CLASSIFIER.read_text(encoding="ascii")

        self.assertNotIn("always_ff @(posedge clk or negedge rst_n) begin", pbm_text)
        self.assertIn("always_ff @(posedge clk) begin", pbm_text)
        self.assertIn("ptr_head_commit <= '0;", pbm_text)
        self.assertIn("ptr_tail <= '0;", pbm_text)

        self.assertIn("always_ff @(posedge clk) begin", classifier_text)
        self.assertNotIn("always_ff @(posedge clk or negedge rst_n) begin", classifier_text)
        self.assertIn("state_q <= STATE_IDLE;", classifier_text)

    def test_shadow_wrapper_txcap_state_is_no_longer_async_reset(self):
        text = SHADOW_WRAPPER.read_text(encoding="ascii")
        self.assertIn("always @(posedge clk) begin", text)
        self.assertNotIn("always @(posedge clk or negedge rst_n) begin", text)
        self.assertIn("if (!rst_n || (SHADOW_INJECT_ONLY == 0)) begin", text)

    def test_shadow_inject_path_state_is_no_longer_async_reset(self):
        text = SHADOW_INJECT_PATH.read_text(encoding="ascii")
        self.assertIn("always_ff @(posedge clk) begin", text)
        self.assertNotIn("always_ff @(posedge clk or negedge rst_n) begin", text)
        self.assertIn("inj_packet_complete <= 1'b0;", text)


if __name__ == "__main__":
    unittest.main()
