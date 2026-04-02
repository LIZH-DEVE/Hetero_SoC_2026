import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
TB = REPO_ROOT / "tb"

FETCHER_TB = TB / "tb_dma_desc_fetcher_doorbell_sanity.sv"
ENGINE_TB = TB / "tb_dma_raw_copy_engine.sv"
SUBSYSTEM_TB = TB / "tb_dma_raw_copy_subsystem.sv"


class TestDmaPhase23BenchAcceptance(unittest.TestCase):
    def test_fetcher_bench_covers_stream_error_and_writeback_barrier(self):
        text = FETCHER_TB.read_text(encoding="ascii")

        self.assertIn("DMA_DESC_CTRL_STREAM_TLAST", text)
        self.assertIn("DMA_DESC_ACTUAL_LEN_BYTE_OFFSET", text)
        self.assertIn("completion event must wait for the final CSW write-back response", text)
        self.assertIn("head pointer must not advance until the final CSW write-back response", text)
        self.assertIn("DMA_DESC_CSW_STS_OVERFLOW_OR_MISSING_TLAST", text)

    def test_subsystem_bench_covers_phase2_multidescriptor_irq_and_wrap(self):
        text = SUBSYSTEM_TB.read_text(encoding="ascii")

        for token in (
            'wait_for_csw_done_at(DESC0_IDX, 40000, "multi-descriptor desc0")',
            'wait_for_csw_done_at(DESC1_IDX, 40000, "multi-descriptor desc1")',
            'wait_for_csw_done_at(DESC2_IDX, 40000, "multi-descriptor desc2")',
            "DMA_CSR_IRQ_COALESCE_COUNT, 32'd2",
            "DMA_CSR_IRQ_COALESCE_TIMEOUT, 32'd12",
            "count-threshold IRQ",
            "timeout-threshold IRQ",
            "wrap-around desc3",
            "wrap-around desc0",
            "actual_len writeback mismatch",
        ):
            self.assertIn(token, text)

    def test_subsystem_bench_covers_phase3_stream_short_exact_and_overflow(self):
        text = SUBSYSTEM_TB.read_text(encoding="ascii")

        for token in (
            "stream_send_beat(32'hCAFE_0001, 1'b0)",
            "stream_send_beat(32'hCAFE_0002, 1'b1)",
            "wait_for_csw_done_at(DESC0_IDX, 40000, \"stream short-frame desc0\")",
            "stream short-frame actual_len mismatch",
            "stream short-frame wrote beyond TLAST",
            "stream_send_beat(32'hFACE_1001, 1'b0)",
            "stream_send_beat(32'hFACE_1002, 1'b0)",
            "stream_send_beat(32'hFACE_1003, 1'b1)",
            "wait_for_csw_done_at(DESC0_IDX, 40000, \"stream exact-fit desc0\")",
            "stream exact-fit actual_len mismatch",
            "stream exact-fit payload mismatch",
            "stream overflow completion must stay low until the final CSW write-back response",
            "wait_for_csw_done_at(DESC0_IDX, 40000, \"stream overflow desc0\")",
            "DMA_DESC_CSW_STS_OVERFLOW_OR_MISSING_TLAST",
            "stream overflow actual_len mismatch",
            "stream overflow status mismatch",
        ):
            self.assertIn(token, text)

    def test_engine_bench_covers_post_overflow_tail_drain_recovery(self):
        text = ENGINE_TB.read_text(encoding="ascii")

        for token in (
            "stream_send_beat_with_timeout(32'hBEEF_2003, 1'b1, 200, \"overflow tail drain\")",
            "stream overflow drain must release readiness after TLAST is consumed",
            "stream_send_beat_with_timeout(32'hD00D_3001, 1'b0, 200, \"post-overflow frame beat0\")",
            "stream_send_beat_with_timeout(32'hD00D_3002, 1'b1, 200, \"post-overflow frame beat1\")",
            "post-overflow frame must complete cleanly after tail drain",
            "tail-drain recovery",
        ):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
