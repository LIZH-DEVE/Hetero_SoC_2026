import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
CLASSIFIER = REPO_ROOT / "rtl" / "core" / "dma" / "udp_dma_ingress_classifier.sv"
WRAPPER = REPO_ROOT / "rtl" / "top" / "dma_gateway_hybrid_board_wrapper.v"
SUBSYSTEM = REPO_ROOT / "rtl" / "top" / "crypto_dma_subsystem.sv"
BRIDGE = REPO_ROOT / "rtl" / "core" / "crypto" / "crypto_bridge_top.sv"


class TestShadowMirrorCBCReadinessContracts(unittest.TestCase):
    def test_classifier_exposes_cbc_packet_length_guard(self):
        text = CLASSIFIER.read_text(encoding="utf-8")

        self.assertIn(
            "CBC payload requires a 16-byte IV plus 16-byte aligned data",
            text,
        )
        self.assertIn("o_drop_cbc_length_invalid_count", text)
        self.assertIn(
            "CBC readiness metadata must not alter current shadow datapath admission",
            text,
        )
        self.assertNotIn("end else if (cbc_length_invalid_now) begin", text)

    def test_wrapper_threads_classifier_packet_metadata_into_subsystem(self):
        text = WRAPPER.read_text(encoding="utf-8")

        for token in (
            "classifier_dma_pkt_start",
            "classifier_dma_pkt_end",
            "classifier_dma_cbc_mode",
            "classifier_dma_iv_header",
            ".rx_wr_pkt_start(classifier_dma_pkt_start)",
            ".rx_wr_pkt_end(classifier_dma_pkt_end)",
            ".rx_wr_cbc_mode(classifier_dma_cbc_mode)",
            ".rx_wr_iv_header(classifier_dma_iv_header)",
        ):
            self.assertIn(token, text)

    def test_subsystem_carries_packet_metadata_into_bridge_staging(self):
        text = SUBSYSTEM.read_text(encoding="utf-8")

        self.assertIn("bridge_pkt_start", text)
        self.assertIn("bridge_pkt_end", text)
        self.assertIn("bridge_pkt_cbc_mode", text)
        self.assertIn("bridge_iv_header", text)

    def test_bridge_declares_packet_atomic_cbc_mode(self):
        text = BRIDGE.read_text(encoding="utf-8")

        self.assertIn("CBC mode is packet-atomic on the active shadow path", text)
        self.assertIn("cbc_pkt_active", text)
        self.assertIn("cbc_iv_header", text)


if __name__ == "__main__":
    unittest.main()
