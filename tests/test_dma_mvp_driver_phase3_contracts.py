import pathlib
import re
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"
RTL = REPO_ROOT / "rtl"

DRIVER_H = HCS_SOC / "dma_mvp_ps_driver_ref.h"
DRIVER_C = HCS_SOC / "dma_mvp_ps_driver_ref.c"
CONTRACT_H = HCS_SOC / "dma_hw_regs.h"
ENGINE_SV = RTL / "core" / "dma" / "dma_raw_copy_engine.sv"
SUBSYSTEM_SV = RTL / "top" / "dma_raw_copy_subsystem.sv"


class TestDmaMvpDriverPhase3Contracts(unittest.TestCase):
    def test_fixed_mode_actual_len_support_exists(self):
        header = DRIVER_H.read_text(encoding="ascii")
        source = DRIVER_C.read_text(encoding="ascii")

        self.assertIn("uint32_t dma_ring_read_actual_len(volatile dma_ring_desc_t *desc);", header)
        self.assertIn("desc->actual_len = 0u;", source)
        self.assertRegex(
            source,
            r"uint32_t dma_ring_read_actual_len\(volatile dma_ring_desc_t \*desc\)[\s\S]*?"
            r"dma_ring_invalidate_desc\(desc\);[\s\S]*?return \*dma_ring_desc_actual_len_ptr\(desc\);",
        )

    def test_stream_mode_contract_and_ps_api_exist(self):
        header = DRIVER_H.read_text(encoding="ascii")
        source = DRIVER_C.read_text(encoding="ascii")
        contract = CONTRACT_H.read_text(encoding="ascii")

        self.assertIn("DMA_DESC_CTRL_BIT_STREAM_TLAST", contract)
        self.assertIn("DMA_DESC_CTRL_STREAM_TLAST", contract)
        self.assertIn("dma_ring_submit_stream", header)
        self.assertIn("dma_ring_submit_stream", source)

    def test_engine_declares_explicit_stream_axis_ingress(self):
        text = ENGINE_SV.read_text(encoding="ascii")

        for token in (
            "input  logic [DATA_WIDTH-1:0]   s_axis_tdata",
            "input  logic                    s_axis_tvalid",
            "output logic                    s_axis_tready",
            "input  logic                    s_axis_tlast",
        ):
            self.assertIn(token, text)

    def test_subsystem_exposes_and_forwards_stream_axis_ingress(self):
        text = SUBSYSTEM_SV.read_text(encoding="ascii")

        for token in (
            "input  logic [DATA_WIDTH-1:0]  s_axis_tdata",
            "input  logic                   s_axis_tvalid",
            "output logic                   s_axis_tready",
            "input  logic                   s_axis_tlast",
        ):
            self.assertIn(token, text)

        self.assertRegex(
            text,
            r"\.s_axis_tdata\(s_axis_tdata\)[\s\S]*?"
            r"\.s_axis_tvalid\(s_axis_tvalid\)[\s\S]*?"
            r"\.s_axis_tready\(s_axis_tready\)[\s\S]*?"
            r"\.s_axis_tlast\(s_axis_tlast\)",
        )

    def test_engine_no_longer_claims_capacity_bounded_fake_stream_mode(self):
        text = ENGINE_SV.read_text(encoding="ascii")

        self.assertNotIn("actual_len collapses to the requested", text)
        self.assertNotIn("memory-backed raw-copy datapath still synthesizes TLAST", text)


if __name__ == "__main__":
    unittest.main()
