import pathlib
import re
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
RTL = REPO_ROOT / "rtl"
HCS_SOC = REPO_ROOT / "HCS_SOC"

WRAPPER_V = RTL / "top" / "dma_gateway_hybrid_perf_proof_core.v"
EXPORT_TCL = HCS_SOC / "export_dma_gateway_hybrid_perf_proof_xsa.tcl"
EXPORT_PS1 = HCS_SOC / "export_dma_gateway_hybrid_perf_proof_xsa.ps1"
BOOT_PS1 = HCS_SOC / "build_ax7020_dma_gateway_hybrid_perf_proof_boot.ps1"


class TestDmaGatewayHybridPerfProofContracts(unittest.TestCase):
    def test_minimal_perf_proof_wrapper_strips_network_path(self):
        text = WRAPPER_V.read_text(encoding="ascii")

        for token in (
            "module dma_gateway_hybrid_perf_proof_core",
            "axil_csr #(",
            "crypto_dma_subsystem #(",
            ".CRYPTO_NUM_INSTANCES(2)",
            ".rx_wr_valid(1'b0)",
            ".rx_wr_data(32'd0)",
            ".rx_wr_last(1'b0)",
            ".tx_axis_tready(1'b0)",
            "assign dma_irq = 1'b0;",
        ):
            self.assertIn(token, text)

        for forbidden in (
            "network_stage1_path",
            "udp_dma_ingress_classifier",
            "udp_gateway_shadow_inject_path",
        ):
            self.assertNotIn(forbidden, text)

    def test_perf_proof_export_uses_minimal_wrapper_and_dual_windows(self):
        tcl = EXPORT_TCL.read_text(encoding="ascii")
        ps1 = EXPORT_PS1.read_text(encoding="ascii")
        boot = BOOT_PS1.read_text(encoding="ascii")

        for token in (
            'set raw_bd_name "dma_gateway_hybrid_perf_proof"',
            '{"rtl/top/dma_gateway_hybrid_perf_proof_core.v" "Verilog"}',
            "create_bd_cell -type module -reference dma_gateway_hybrid_perf_proof_core dma_gateway_hybrid_perf_proof_0",
            "connect_bd_intf_net [get_bd_intf_pins dma_gateway_hybrid_perf_proof_0/s_axil_ctrl] [get_bd_intf_pins ps7_0_axi_periph/M00_AXI]",
            "connect_bd_intf_net [get_bd_intf_pins dma_gateway_hybrid_perf_proof_0/s_axil_dma] [get_bd_intf_pins ps7_0_axi_periph/M01_AXI]",
            "connect_bd_intf_net [get_bd_intf_pins dma_gateway_hybrid_perf_proof_0/m_axi_dma_wr] [get_bd_intf_pins axi_mem_intercon/S00_AXI]",
            "connect_bd_intf_net [get_bd_intf_pins dma_gateway_hybrid_perf_proof_0/m_axi_fetcher] [get_bd_intf_pins axi_mem_intercon/S01_AXI]",
            "connect_bd_intf_net [get_bd_intf_pins dma_gateway_hybrid_perf_proof_0/m_axi_s2mm] [get_bd_intf_pins axi_mem_intercon/S02_AXI]",
            "set_property top dma_gateway_hybrid_perf_proof_wrapper [current_fileset]",
            'Join-Path $workspace "export_dma_gateway_hybrid_perf_proof_xsa.ps1"',
            'Join-Path $workspace "dma_gateway_hybrid_perf_proof_wrapper.xsa"',
        ):
            self.assertIn(token, tcl + "\n" + ps1 + "\n" + boot)

        self.assertRegex(
            tcl,
            r"assign_bd_address -offset 0x40000000 -range 4K[\s\\\n]+"
            r"-target_address_space \[get_bd_addr_spaces processing_system7_0/Data\][\s\\\n]+"
            r"\[get_bd_addr_segs dma_gateway_hybrid_perf_proof_0/s_axil_ctrl/reg0\] -force",
        )
        self.assertRegex(
            tcl,
            r"assign_bd_address -offset 0x40001000 -range 4K[\s\\\n]+"
            r"-target_address_space \[get_bd_addr_spaces processing_system7_0/Data\][\s\\\n]+"
            r"\[get_bd_addr_segs dma_gateway_hybrid_perf_proof_0/s_axil_dma/reg0\] -force",
        )


if __name__ == "__main__":
    unittest.main()
