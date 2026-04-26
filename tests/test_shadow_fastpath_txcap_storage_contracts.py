import pathlib
import re
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
SHADOW_WRAPPER = REPO_ROOT / "rtl" / "top" / "dma_gateway_hybrid_board_wrapper.v"


class TestShadowFastpathEgressContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SHADOW_WRAPPER.read_text(encoding="ascii")

    def test_fastpath_hit_retargets_into_zero_copy_egress_states(self):
        text = self.text

        for token in (
            "localparam [2:0] FASTPATH_ROUTE_EGRESS_REPLAY = 3'd4;",
            "localparam [2:0] FASTPATH_ROUTE_EGRESS_DMA = 3'd5;",
            "wire [31:0]           subsys_tx_axis_tdata;",
            "wire                  subsys_tx_axis_tvalid;",
            "wire                  subsys_tx_axis_tlast;",
            "wire [3:0]            subsys_tx_axis_tkeep;",
            "wire [31:0]           egress_tx_axis_tdata;",
            "wire                  egress_tx_axis_tvalid;",
            "wire                  egress_tx_axis_tlast;",
            "wire [3:0]            egress_tx_axis_tkeep;",
            "wire                  fastpath_egress_selected;",
        ):
            self.assertIn(token, text)

        self.assertIn("fastpath_route_state_q <= FASTPATH_ROUTE_EGRESS_REPLAY;", text)
        self.assertNotIn("fastpath_route_state_q <= FASTPATH_ROUTE_TXCAP;", text)

    def test_fastpath_hit_no_longer_copies_headers_into_txcap_mainline(self):
        text = self.text

        hit_match = re.search(
            r"\(\(\(aclf_tdata\[15:0\] - 16'd8\) >> 2\) \+ FASTPATH_HDR_WORDS <= FASTPATH_TXCAP_DEPTH\)\) begin(?P<body>.*?)fastpath_route_state_q <= FASTPATH_ROUTE_EGRESS_REPLAY;",
            text,
            re.S,
        )
        self.assertIsNotNone(hit_match, "FastPath zero-copy egress hit block missing")
        hit_body = hit_match.group("body")

        self.assertNotIn("txcap_header_mem[0] <=", hit_body)
        self.assertNotIn("txcap_payload_wr_ptr_q <=", hit_body)
        self.assertNotIn("txcap_count_q <=", hit_body)
        self.assertIn("payload_words_q <=", hit_body)
        self.assertIn("fastpath_last_hit_q <= 1'b1;", hit_body)
        self.assertIn("fastpath_last_reason_q <= FASTPATH_REASON_HIT;", hit_body)

    def test_zero_copy_egress_replay_and_payload_backpressure_contract(self):
        text = self.text

        for token in (
            "assign egress_tx_axis_tdata = (fastpath_route_state_q == FASTPATH_ROUTE_EGRESS_REPLAY) ?",
            "assign egress_tx_axis_tvalid = (fastpath_route_state_q == FASTPATH_ROUTE_EGRESS_REPLAY) ? 1'b1 :",
            "assign egress_tx_axis_tlast = (fastpath_route_state_q == FASTPATH_ROUTE_EGRESS_REPLAY) ?",
            "assign egress_tx_axis_tkeep = 4'hF;",
            "assign fastpath_egress_selected =",
            "assign subsys_tx_axis_tready = fastpath_egress_selected ? 1'b0 : i_tx_axis_tready;",
            "assign o_tx_axis_tdata = fastpath_egress_selected ? egress_tx_axis_tdata : subsys_tx_axis_tdata;",
            "assign o_tx_axis_tvalid = fastpath_egress_selected ? egress_tx_axis_tvalid : subsys_tx_axis_tvalid;",
            "assign o_tx_axis_tlast = fastpath_egress_selected ? egress_tx_axis_tlast : subsys_tx_axis_tlast;",
            "assign o_tx_axis_tkeep = fastpath_egress_selected ? egress_tx_axis_tkeep : subsys_tx_axis_tkeep;",
            "((fastpath_route_state_q == FASTPATH_ROUTE_EGRESS_DMA) ? i_tx_axis_tready : 1'b0)",
        ):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
