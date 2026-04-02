import importlib.util
import json
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = REPO_ROOT / "HCS_SOC" / "dma_contract_manifest.json"
GENERATOR_PATH = REPO_ROOT / "HCS_SOC" / "generate_dma_contract_artifacts.py"
C_HEADER_PATH = REPO_ROOT / "HCS_SOC" / "dma_hw_regs.h"
SV_PKG_PATH = REPO_ROOT / "rtl" / "inc" / "dma_csr_pkg.sv"
BFM_TASKS_PATH = REPO_ROOT / "tb" / "tb_ps_bfm_tasks.sv"


def _load_generator():
    spec = importlib.util.spec_from_file_location("generate_dma_contract_artifacts", GENERATOR_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class DmaContractGenerationTests(unittest.TestCase):
    def test_contract_artifacts_exist(self):
        self.assertTrue(MANIFEST_PATH.exists(), "dma contract manifest missing")
        self.assertTrue(GENERATOR_PATH.exists(), "dma contract generator missing")
        self.assertTrue(C_HEADER_PATH.exists(), "generated dma_hw_regs.h missing")
        self.assertTrue(SV_PKG_PATH.exists(), "generated dma_csr_pkg.sv missing")
        self.assertTrue(BFM_TASKS_PATH.exists(), "tb_ps_bfm_tasks.sv missing")

    def test_generated_header_matches_manifest(self):
        generator = _load_generator()
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        expected = generator.render_c_header(manifest)
        actual = C_HEADER_PATH.read_text(encoding="utf-8")
        self.assertEqual(expected, actual)

    def test_generated_sv_package_matches_manifest(self):
        generator = _load_generator()
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        expected = generator.render_sv_package(manifest)
        actual = SV_PKG_PATH.read_text(encoding="utf-8")
        self.assertEqual(expected, actual)

    def test_manifest_freezes_key_contract_values(self):
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))

        self.assertEqual(2, manifest["contract_version"])
        self.assertEqual(0x00, manifest["csr"]["offsets"]["CTRL"])
        self.assertEqual(0x04, manifest["csr"]["offsets"]["STATUS"])
        self.assertEqual(0x40, manifest["csr"]["offsets"]["CACHE_CTRL"])
        self.assertEqual(0x48, manifest["csr"]["offsets"]["LOOPBACK_MODE"])
        self.assertEqual(0x4C, manifest["csr"]["offsets"]["RING_DOORBELL"])
        self.assertEqual(0x50, manifest["csr"]["offsets"]["RING_BASE"])
        self.assertEqual(0x54, manifest["csr"]["offsets"]["RING_HW_HEAD"])
        self.assertEqual(0x58, manifest["csr"]["offsets"]["RING_SW_TAIL"])
        self.assertEqual(0x5C, manifest["csr"]["offsets"]["RING_SIZE"])
        self.assertEqual(0x60, manifest["csr"]["offsets"]["IRQ_ENABLE"])
        self.assertEqual(0x64, manifest["csr"]["offsets"]["IRQ_STATUS"])
        self.assertEqual(0x68, manifest["csr"]["offsets"]["IRQ_ACK"])
        self.assertEqual(0x6C, manifest["csr"]["offsets"]["IRQ_COALESCE_COUNT"])
        self.assertEqual(0x70, manifest["csr"]["offsets"]["IRQ_COALESCE_TIMEOUT"])
        self.assertEqual(0x1, manifest["csr"]["write_values"]["RING_DOORBELL_KICK"])
        self.assertEqual(10, manifest["csr"]["ctrl_bits"]["SOFT_RESET"])
        self.assertEqual(32, manifest["descriptor"]["size_bytes"])
        self.assertEqual(31, manifest["descriptor"]["csw_bits"]["OWNER"])
        self.assertEqual(30, manifest["descriptor"]["csw_bits"]["DONE"])
        self.assertEqual(29, manifest["descriptor"]["csw_bits"]["ERR"])
        self.assertEqual("ACTUAL_LEN", manifest["descriptor"]["fields"][5]["name"])
        self.assertEqual(20, manifest["descriptor"]["fields"][5]["byte_offset"])
        self.assertEqual(30, manifest["descriptor"]["ctrl_bits"]["STREAM_TLAST"])
        self.assertEqual(32, manifest["cache"]["line_bytes"])
        self.assertEqual(32, manifest["cache"]["alignment_bytes"])
        self.assertEqual(32, manifest["cache"]["raw_copy_len_multiple"])
        self.assertEqual(2, manifest["ring"]["min_size"])
        self.assertTrue(manifest["ring"]["keep_one_slot_open"])
        self.assertTrue(manifest["ring"]["full_when_next_tail_equals_hw_head"])
        self.assertEqual(-5, manifest["ring"]["submit_full_rc"])
        self.assertEqual(
            ["flush_desc_and_src", "dsb", "write_sw_tail", "dsb", "write_doorbell"],
            manifest["sequences"]["submission"],
        )
        self.assertEqual(
            ["poll_csw_success", "invalidate_dst", "dsb", "memcmp"],
            manifest["sequences"]["validation"],
        )
        self.assertEqual(["dma_state_machine", "axis_fifo"], manifest["soft_reset"]["clears"])
        self.assertEqual(
            ["fifo_empty", "s2mm_no_pending_beat", "fresh_csw_observation"],
            manifest["soft_reset"]["retry_requires"],
        )
        self.assertEqual(512, manifest["raw_copy"]["fifo_depth"])
        self.assertEqual("BRAM", manifest["raw_copy"]["fifo_memory"])
        self.assertEqual(1, manifest["raw_copy"]["tlast_width"])
        self.assertEqual(8, manifest["irq"]["default_coalesce_count"])
        self.assertEqual(5000, manifest["irq"]["default_coalesce_timeout_cycles"])
        self.assertEqual(50000000, manifest["irq"]["timeout_reference_clock_hz"])
        self.assertEqual(100, manifest["irq"]["timeout_reference_window_us"])
        self.assertEqual(0, manifest["irq"]["enable_bits"]["DONE"])
        self.assertEqual(0, manifest["irq"]["status_bits"]["DONE_PENDING"])
        self.assertEqual(0, manifest["irq"]["ack_bits"]["DONE_ACK"])
        self.assertEqual(
            ["payload_wb_b_handshake_complete", "actual_len_wb_b_handshake_complete", "csw_wb_b_handshake_complete"],
            manifest["irq"]["completion_event_requires"],
        )
        self.assertEqual(
            ["payload_wb_b_handshake_complete", "actual_len_wb_b_handshake_complete", "csw_wb_b_handshake_complete"],
            manifest["irq"]["completion_event_sequence"],
        )
        self.assertEqual(
            [
                "read_irq_status",
                "ack_done_pending",
                "schedule_bottom_half",
                "no_polling",
                "no_delay",
                "no_cache_invalidate",
                "no_memcmp",
                "no_long_uart_print",
            ],
            manifest["irq"]["isr_rules"],
        )
        self.assertEqual("requested_len", manifest["stream_mode"]["len_semantics"]["fixed"])
        self.assertEqual("buffer_capacity", manifest["stream_mode"]["len_semantics"]["stream_tlast"])
        self.assertTrue(manifest["stream_mode"]["actual_len_fixed_equals_requested_len"])
        self.assertTrue(manifest["stream_mode"]["actual_len_stream_equals_received_bytes"])
        self.assertEqual(
            ["TDATA", "TVALID", "TREADY", "TLAST"],
            manifest["raw_copy"]["required_axis_signals"],
        )

    def test_generated_artifacts_surface_equivalent_contract_metadata(self):
        c_header = C_HEADER_PATH.read_text(encoding="utf-8")
        sv_pkg = SV_PKG_PATH.read_text(encoding="utf-8")

        self.assertIn("#define DMA_SUBMISSION_STEP_COUNT 5u", c_header)
        self.assertIn("#define DMA_CSR_RING_DOORBELL_KICK 0x00000001u", c_header)
        self.assertIn('#define DMA_SUBMISSION_STEP_0 "flush_desc_and_src"', c_header)
        self.assertIn("#define DMA_VALIDATION_STEP_COUNT 4u", c_header)
        self.assertIn('#define DMA_VALIDATION_STEP_0 "poll_csw_success"', c_header)
        self.assertIn("#define DMA_SOFT_RESET_CLEAR_COUNT 2u", c_header)
        self.assertIn('#define DMA_SOFT_RESET_RETRY_REQUIREMENT_1 "s2mm_no_pending_beat"', c_header)
        self.assertIn('#define DMA_RAW_COPY_FIFO_MEMORY "BRAM"', c_header)
        self.assertIn("#define DMA_RAW_COPY_REQUIRED_AXIS_SIGNAL_COUNT 4u", c_header)
        self.assertIn('#define DMA_RAW_COPY_REQUIRED_AXIS_SIGNAL_3 "TLAST"', c_header)
        self.assertIn("#define DMA_CSR_IRQ_ENABLE 0x00000060u", c_header)
        self.assertIn("#define DMA_CSR_IRQ_STATUS 0x00000064u", c_header)
        self.assertIn("#define DMA_CSR_IRQ_ACK 0x00000068u", c_header)
        self.assertIn("#define DMA_DESC_ACTUAL_LEN_BYTE_OFFSET 0x00000014u", c_header)
        self.assertIn("#define DMA_DESC_CTRL_BIT_STREAM_TLAST 30u", c_header)
        self.assertIn("#define DMA_DESC_CSW_STS_OVERFLOW_OR_MISSING_TLAST 0x00000002u", c_header)
        self.assertIn("#define DMA_IRQ_ENABLE_DONE (1u << DMA_IRQ_ENABLE_BIT_DONE)", c_header)
        self.assertIn("#define DMA_IRQ_STATUS_DONE_PENDING (1u << DMA_IRQ_STATUS_BIT_DONE_PENDING)", c_header)
        self.assertIn("#define DMA_IRQ_ACK_DONE_ACK (1u << DMA_IRQ_ACK_BIT_DONE_ACK)", c_header)
        self.assertIn("#define DMA_IRQ_DEFAULT_COALESCE_COUNT 8u", c_header)
        self.assertIn("#define DMA_IRQ_DEFAULT_COALESCE_TIMEOUT_CYCLES 5000u", c_header)

        self.assertIn("localparam int unsigned DMA_SUBMISSION_STEP_COUNT = 5;", sv_pkg)
        self.assertIn("localparam logic [31:0] DMA_CSR_RING_DOORBELL_KICK = 32'h00000001;", sv_pkg)
        self.assertIn('localparam string DMA_SUBMISSION_STEP_0 = "flush_desc_and_src";', sv_pkg)
        self.assertIn("localparam int unsigned DMA_VALIDATION_STEP_COUNT = 4;", sv_pkg)
        self.assertIn('localparam string DMA_VALIDATION_STEP_0 = "poll_csw_success";', sv_pkg)
        self.assertIn("localparam int unsigned DMA_SOFT_RESET_CLEAR_COUNT = 2;", sv_pkg)
        self.assertIn('localparam string DMA_SOFT_RESET_RETRY_REQUIREMENT_1 = "s2mm_no_pending_beat";', sv_pkg)
        self.assertIn('localparam string DMA_RAW_COPY_FIFO_MEMORY = "BRAM";', sv_pkg)
        self.assertIn("localparam int unsigned DMA_RAW_COPY_REQUIRED_AXIS_SIGNAL_COUNT = 4;", sv_pkg)
        self.assertIn('localparam string DMA_RAW_COPY_REQUIRED_AXIS_SIGNAL_3 = "TLAST";', sv_pkg)
        self.assertIn("localparam logic [31:0] DMA_CSR_IRQ_ENABLE = 32'h00000060;", sv_pkg)
        self.assertIn("localparam logic [31:0] DMA_CSR_IRQ_STATUS = 32'h00000064;", sv_pkg)
        self.assertIn("localparam logic [31:0] DMA_CSR_IRQ_ACK = 32'h00000068;", sv_pkg)
        self.assertIn("localparam int unsigned DMA_DESC_ACTUAL_LEN_BYTE_OFFSET = 20;", sv_pkg)
        self.assertIn("localparam int unsigned DMA_DESC_CTRL_BIT_STREAM_TLAST = 30;", sv_pkg)
        self.assertIn("localparam logic [31:0] DMA_DESC_CSW_STS_OVERFLOW_OR_MISSING_TLAST = 32'h00000002;", sv_pkg)
        self.assertIn("localparam logic [31:0] DMA_IRQ_ENABLE_DONE = 32'h00000001 << DMA_IRQ_ENABLE_BIT_DONE;", sv_pkg)
        self.assertIn("localparam logic [31:0] DMA_IRQ_STATUS_DONE_PENDING = 32'h00000001 << DMA_IRQ_STATUS_BIT_DONE_PENDING;", sv_pkg)
        self.assertIn("localparam logic [31:0] DMA_IRQ_ACK_DONE_ACK = 32'h00000001 << DMA_IRQ_ACK_BIT_DONE_ACK;", sv_pkg)
        self.assertIn("localparam int unsigned DMA_IRQ_DEFAULT_COALESCE_COUNT = 8;", sv_pkg)
        self.assertIn("localparam int unsigned DMA_IRQ_DEFAULT_COALESCE_TIMEOUT_CYCLES = 5000;", sv_pkg)

    def test_bfm_tasks_import_pkg_and_expose_required_sequences(self):
        contents = BFM_TASKS_PATH.read_text(encoding="utf-8")

        self.assertIn("import dma_csr_pkg::*;", contents)
        self.assertIn("task automatic dma_bfm_ring_init", contents)
        self.assertIn("task automatic dma_bfm_submit_raw_copy", contents)
        self.assertIn("task automatic dma_bfm_publish_tail", contents)
        self.assertIn("task automatic dma_bfm_ring_doorbell", contents)
        self.assertIn("DMA_CSR_RING_DOORBELL_KICK", contents)
        self.assertIn("task automatic dma_bfm_poll_csw_done", contents)
        self.assertIn("task automatic dma_bfm_validate_raw_copy", contents)
        self.assertIn("task automatic dma_bfm_soft_reset_clean_retry", contents)
        self.assertIn("DMA_DESC_CSW_ERR", contents)
        self.assertIn("DMA_DESC_CSW_MASK_STS", contents)
        self.assertIn("DMA_RAW_COPY_LEN_MULTIPLE", contents)


if __name__ == "__main__":
    unittest.main()
