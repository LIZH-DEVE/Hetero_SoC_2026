import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
AXIL_CSR = REPO_ROOT / "rtl" / "core" / "axil_csr.sv"


class TestAxilCsrWriteLatchContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = AXIL_CSR.read_text(encoding="ascii")

    def test_axil_csr_latches_write_data_and_strobes_until_write_en_consumes_them(self):
        text = self.text

        for token in (
            "logic [DATA_WIDTH-1:0] wdata_latch;",
            "logic [3:0]            wstrb_latch;",
            "s_axil_wready <= 0; w_received <= 0; wdata_latch <= '0; wstrb_latch <= '0;",
            "wdata_latch <= s_axil_wdata;",
            "wstrb_latch <= s_axil_wstrb;",
            "reg_ctrl <= apply_wstrb(reg_ctrl, wdata_latch, wstrb_latch);",
            "if (wstrb_latch[0] && wdata_latch[0]) begin",
            "if (wstrb_latch[1] && wdata_latch[10]) o_soft_reset <= 1'b1;",
            "8'h48: reg_loopback_mode <= apply_wstrb(reg_loopback_mode, wdata_latch, wstrb_latch);",
            "8'h50: reg_ring_base <= apply_wstrb(reg_ring_base, wdata_latch, wstrb_latch);",
            "8'h58: reg_ring_tail <= apply_wstrb(reg_ring_tail, wdata_latch, wstrb_latch);",
            "8'h5C: reg_ring_size <= apply_wstrb(reg_ring_size, wdata_latch, wstrb_latch);",
            "if (wstrb_latch[0] && wdata_latch[DMA_COUNTER_CTRL_BIT_CLEAR_ALL]) begin",
            "if (wstrb_latch[0] && wdata_latch[DMA_COUNTER_CTRL_BIT_SNAPSHOT]) begin",
        ):
            self.assertIn(token, text)

        for token in (
            "apply_wstrb(reg_ctrl, s_axil_wdata, s_axil_wstrb)",
            "if (s_axil_wstrb[0] && s_axil_wdata[0]) begin",
            "if (s_axil_wstrb[1] && s_axil_wdata[10]) o_soft_reset <= 1'b1;",
            "if (s_axil_wstrb[0] && s_axil_wdata[DMA_COUNTER_CTRL_BIT_CLEAR_ALL]) begin",
            "if (s_axil_wstrb[0] && s_axil_wdata[DMA_COUNTER_CTRL_BIT_SNAPSHOT]) begin",
        ):
            self.assertNotIn(token, text)


if __name__ == "__main__":
    unittest.main()
