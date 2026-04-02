import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
TB = REPO_ROOT / "tb"

BOARD_STREAM_TB = TB / "tb_dma_stream_smoke_board_wrapper.sv"


class TestDmaPhase3BoardStreamAcceptance(unittest.TestCase):
    def test_board_stream_bench_exists_and_describes_dummy_source_flow(self):
        text = BOARD_STREAM_TB.read_text(encoding="ascii")

        for token in (
            "module tb_dma_stream_smoke_board_wrapper",
            "dma_stream_smoke_board_wrapper",
            "s_axil_dma_awaddr",
            "s_axil_dummy_awaddr",
            "stream_dummy_source",
            "0x40000000",
            "0x40001000",
            "PACKET_LEN",
            "DMA stream smoke image",
            "STREAM_STAGE EXACT_FIT PASS actual_len=1024",
            "STREAM_STAGE SHORT PASS actual_len=64",
            "STREAM_STAGE OVERFLOW PASS actual_len=64",
            "DMA stream smoke PASS",
            "final CSW writeback response",
            "hold_payload_resp_low",
            "hold_wb_resp_low",
            "saw_completion_during_payload_hold_q",
            "saw_completion_during_wb_hold_q",
            "saw_irq_during_wb_hold_q",
            "STREAM_STAGE EXACT_FIT payload write response barrier was violated before payload B completed",
            "STREAM_STAGE EXACT_FIT wrote beyond capacity",
            "STREAM_STAGE OVERFLOW wrote beyond capacity",
            "completion became software-visible before the final CSW writeback response",
        ):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
