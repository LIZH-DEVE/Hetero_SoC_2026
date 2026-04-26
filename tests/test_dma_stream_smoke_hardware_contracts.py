import pathlib
import re
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
RTL = REPO_ROOT / "rtl"
HCS_SOC = REPO_ROOT / "HCS_SOC"

DUMMY_SOURCE_SV = RTL / "core" / "dma" / "stream_dummy_source.sv"
STREAM_WRAPPER_SV = RTL / "top" / "dma_stream_smoke_board_wrapper.v"
EXPORT_TCL = HCS_SOC / "export_dma_stream_smoke_xsa.tcl"
EXPORT_PS1 = HCS_SOC / "export_dma_stream_smoke_xsa.ps1"


class TestDmaStreamSmokeHardwareContracts(unittest.TestCase):
    def test_stream_smoke_hardware_assets_exist(self):
        for required in (
            DUMMY_SOURCE_SV,
            STREAM_WRAPPER_SV,
            EXPORT_TCL,
            EXPORT_PS1,
        ):
            self.assertTrue(required.exists(), f"Expected stream-smoke asset missing: {required}")

    def test_stream_smoke_wrapper_owns_two_axil_windows_and_internal_stream_path(self):
        text = STREAM_WRAPPER_SV.read_text(encoding="ascii")

        for token in (
            "s_axil_dma_awaddr",
            "s_axil_dummy_awaddr",
            "dma_raw_copy_subsystem",
            "stream_dummy_source",
            ".s_axis_tdata(dummy_tdata)",
            ".s_axis_tvalid(dummy_tvalid)",
            ".s_axis_tready(dummy_tready)",
            ".s_axis_tlast(dummy_tlast)",
        ):
            self.assertIn(token, text)

    def test_export_chain_uses_dedicated_stream_wrapper_and_non_overlapping_gp0_windows(self):
        text = EXPORT_TCL.read_text(encoding="ascii")

        self.assertIn('set raw_bd_name "stream_smoke_dma"', text)
        self.assertIn("create_bd_cell -type module -reference dma_stream_smoke_board_wrapper dma_stream_smoke_subsystem_0", text)
        self.assertIn("set_property -dict [list CONFIG.NUM_MI {2}] [get_bd_cells ps7_0_axi_periph]", text)
        self.assertIn("connect_bd_intf_net [get_bd_intf_pins dma_stream_smoke_subsystem_0/s_axil_dma] [get_bd_intf_pins ps7_0_axi_periph/M00_AXI]", text)
        self.assertIn("connect_bd_intf_net [get_bd_intf_pins dma_stream_smoke_subsystem_0/s_axil_dummy] [get_bd_intf_pins ps7_0_axi_periph/M01_AXI]", text)

        self.assertRegex(
            text,
            r"assign_bd_address -offset 0x40000000 -range 4K[\s\\\n]+"
            r"-target_address_space \[get_bd_addr_spaces processing_system7_0/Data\][\s\\\n]+"
            r"\[get_bd_addr_segs dma_stream_smoke_subsystem_0/s_axil_dma/reg0\] -force",
        )
        self.assertRegex(
            text,
            r"assign_bd_address -offset 0x40001000 -range 4K[\s\\\n]+"
            r"-target_address_space \[get_bd_addr_spaces processing_system7_0/Data\][\s\\\n]+"
            r"\[get_bd_addr_segs dma_stream_smoke_subsystem_0/s_axil_dummy/reg0\] -force",
        )

    def test_export_wrapper_keeps_hp0_path_live(self):
        text = EXPORT_TCL.read_text(encoding="ascii")

        for token in (
            "set_property CONFIG.PCW_USE_S_AXI_HP0 {1} [get_bd_cells processing_system7_0]",
            "connect_bd_intf_net [get_bd_intf_pins axi_mem_intercon/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]",
            "assign_bd_address -offset 0x00000000 -range 512M",
        ):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
