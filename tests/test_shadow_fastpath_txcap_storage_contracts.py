import pathlib
import re
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
SHADOW_WRAPPER = REPO_ROOT / "rtl" / "top" / "dma_gateway_hybrid_board_wrapper.v"


class TestShadowFastpathTxcapStorageContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SHADOW_WRAPPER.read_text(encoding="ascii")

    def test_txcap_header_storage_is_decoupled_from_replay_header_buffer(self):
        text = self.text

        self.assertIn(
            "reg  [31:0]           txcap_header_mem [0:FASTPATH_HDR_WORDS-1];",
            text,
        )

        pop_match = re.search(
            r"else if \(txcap_pop && \(txcap_count_q != 0\)\) begin(?P<body>.*?)\n\s*end\n\n\s*if \(acl_drop_pulse\) begin",
            text,
            re.S,
        )
        self.assertIsNotNone(pop_match, "TXCAP pop handling block missing")
        pop_body = pop_match.group("body")
        self.assertIn("txcap_header_mem[txcap_rd_ptr_q + 9'd1]", pop_body)
        self.assertNotIn("fastpath_header_mem[txcap_rd_ptr_q + 9'd1]", pop_body)

        hit_match = re.search(
            r"\(\(\(aclf_tdata\[15:0\] - 16'd8\) >> 2\) \+ FASTPATH_HDR_WORDS <= FASTPATH_TXCAP_DEPTH\)\) begin(?P<body>.*?)fastpath_route_state_q <= FASTPATH_ROUTE_TXCAP;",
            text,
            re.S,
        )
        self.assertIsNotNone(hit_match, "FastPath TXCAP hit path missing")
        hit_body = hit_match.group("body")
        for token in (
            "txcap_header_mem[0] <= fastpath_header_mem[0];",
            "txcap_header_mem[1] <= fastpath_header_mem[1];",
            "txcap_header_mem[2] <= fastpath_header_mem[2];",
            "txcap_header_mem[3] <= fastpath_header_mem[3];",
            "txcap_header_mem[4] <= fastpath_header_mem[4];",
            "txcap_header_mem[5] <= fastpath_header_mem[5];",
            "txcap_header_mem[6] <= fastpath_header_mem[6];",
            "txcap_header_mem[7] <= fastpath_header_mem[7];",
            "txcap_header_mem[8] <= fastpath_header_mem[8];",
            "txcap_header_mem[9] <= fastpath_header_mem[9];",
            "txcap_header_mem[10] <= aclf_tdata;",
        ):
            self.assertIn(token, hit_body)


if __name__ == "__main__":
    unittest.main()
