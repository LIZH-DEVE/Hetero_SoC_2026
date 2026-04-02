import pathlib
import re
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
RTL = REPO_ROOT / "rtl"
HCS_SOC = REPO_ROOT / "HCS_SOC"

WRAPPER_SV = RTL / "top" / "dma_stream_smoke_board_wrapper.v"
DUMMY_SV = RTL / "core" / "dma" / "stream_dummy_source.sv"
EXPORT_TCL = HCS_SOC / "export_dma_stream_smoke_xsa.tcl"
EXPORT_PS1 = HCS_SOC / "export_dma_stream_smoke_xsa.ps1"


class TestDmaStreamSmokeExportContracts(unittest.TestCase):
    def test_stream_smoke_wrapper_exposes_two_axil_slaves_and_dummy_source(self):
        text = WRAPPER_SV.read_text(encoding="ascii")

        for token in (
            "module dma_stream_smoke_board_wrapper",
            "s_axil_dma_awaddr",
            "s_axil_dummy_awaddr",
            "stream_dummy_source",
            ".s_axis_tdata(",
            ".s_axis_tvalid(",
            ".s_axis_tready(",
            ".s_axis_tlast(",
            ".s_axil_awaddr(s_axil_dummy_awaddr)",
            ".s_axil_awaddr(s_axil_dma_awaddr)",
        ):
            self.assertIn(token, text)

    def test_dummy_source_contract_is_word_granular_and_pattern_fixed(self):
        text = DUMMY_SV.read_text(encoding="ascii")

        for token in (
            "module stream_dummy_source",
            "PACKET_LEN",
            "packet_len",
            "m_axis_tdata",
            "m_axis_tvalid",
            "m_axis_tready",
            "m_axis_tlast",
            "must be a multiple of 4",
            "byte n on the stream is n & 8'hFF",
        ):
            self.assertIn(token, text)

    def test_export_chain_uses_dedicated_stream_smoke_wrapper_and_two_axil_windows(self):
        tcl = EXPORT_TCL.read_text(encoding="ascii")
        ps1 = EXPORT_PS1.read_text(encoding="ascii")

        for token in (
            'set raw_bd_name "stream_smoke_dma"',
            "dma_stream_smoke_board_wrapper",
            "create_bd_cell -type module -reference dma_stream_smoke_board_wrapper dma_stream_smoke_subsystem_0",
            "set_property -dict [list CONFIG.NUM_MI {2}] [get_bd_cells ps7_0_axi_periph]",
            "connect_bd_intf_net [get_bd_intf_pins dma_stream_smoke_subsystem_0/s_axil_dma] [get_bd_intf_pins ps7_0_axi_periph/M00_AXI]",
            "connect_bd_intf_net [get_bd_intf_pins dma_stream_smoke_subsystem_0/s_axil_dummy] [get_bd_intf_pins ps7_0_axi_periph/M01_AXI]",
            "stream_smoke_dma_wrapper.xsa",
        ):
            self.assertIn(token, tcl)

        self.assertRegex(
            tcl,
            r"assign_bd_address -offset 0x40000000 -range 4K[\s\\\n]+"
            r"-target_address_space \[get_bd_addr_spaces processing_system7_0/Data\][\s\\\n]+"
            r"\[get_bd_addr_segs dma_stream_smoke_subsystem_0/s_axil_dma/reg0\] -force",
        )
        self.assertRegex(
            tcl,
            r"assign_bd_address -offset 0x40001000 -range 4K[\s\\\n]+"
            r"-target_address_space \[get_bd_addr_spaces processing_system7_0/Data\][\s\\\n]+"
            r"\[get_bd_addr_segs dma_stream_smoke_subsystem_0/s_axil_dummy/reg0\] -force",
        )

        self.assertIn("export_dma_stream_smoke_xsa.tcl", ps1)
        self.assertIn("stream_smoke_dma_wrapper.xsa", ps1)


if __name__ == "__main__":
    unittest.main()
