import pathlib
import re
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

DRIVER_H = HCS_SOC / "dma_mvp_ps_driver_ref.h"
DRIVER_C = HCS_SOC / "dma_mvp_ps_driver_ref.c"
CONTRACT_H = HCS_SOC / "dma_hw_regs.h"


class TestDmaMvpDriverPhase2Contracts(unittest.TestCase):
    def test_header_declares_phase2_irq_and_ring_helpers(self):
        text = DRIVER_H.read_text(encoding="ascii")

        for symbol in (
            "dma_ring_get_hw_head",
            "dma_ring_get_free_slots",
            "dma_ring_ring_doorbell",
            "dma_ring_submit_raw_copy_nodoorbell",
            "dma_ring_submit_stream",
            "dma_ring_irq_enable",
            "dma_ring_irq_disable",
            "dma_ring_irq_set_coalescing",
            "dma_ring_irq_get_coalesce_count",
            "dma_ring_irq_get_coalesce_timeout",
            "dma_ring_irq_status",
            "dma_ring_irq_ack",
            "dma_ring_irq_top_half",
            "dma_ring_read_actual_len",
        ):
            self.assertIn(symbol, text)

    def test_submit_reads_hw_head_and_keeps_one_slot_open(self):
        text = DRIVER_C.read_text(encoding="ascii")

        self.assertIn("hw_head = dma_ring_get_hw_head(ctx);", text)
        self.assertIn("next_tail = (uint16_t)((ctx->sw_tail + 1u) % ctx->ring_size);", text)
        self.assertIn("if (next_tail == hw_head) {", text)
        self.assertIn("return -5;", text)
        self.assertIn("return (uint16_t)(ctx->ring_size - used - 1u);", text)
        self.assertLess(
            text.index("if (next_tail == hw_head) {"),
            text.index("desc = &ctx->ring_base[ctx->sw_tail];"),
            "ring-full guard must run before descriptor writeback begins",
        )
        self.assertLess(
            text.index("if (next_tail == hw_head) {"),
            text.index("ctx->sw_tail = next_tail;"),
            "ring-full guard must run before software tail advances",
        )
        self.assertRegex(
            text,
            r"if \(ctx == 0 \|\| ctx->ring_base == 0 \|\| ctx->ring_size < 2u\)\s*\{\s*return -1;",
        )

    def test_driver_supports_staged_fill_without_immediate_doorbell(self):
        header_text = DRIVER_H.read_text(encoding="ascii")
        impl_text = DRIVER_C.read_text(encoding="ascii")

        self.assertIn("dma_ring_ring_doorbell", header_text)
        self.assertIn("dma_ring_submit_raw_copy_nodoorbell", header_text)
        self.assertRegex(
            impl_text,
            r"int dma_ring_submit_raw_copy_nodoorbell\(dma_ring_ctx_t \*ctx,\s*"
            r"uint32_t dst_addr,\s*"
            r"uint32_t src_addr,\s*"
            r"uint32_t byte_len,\s*"
            r"const void \*payload_addr,\s*"
            r"uint32_t payload_len\)",
        )
        self.assertRegex(
            impl_text,
            r"return dma_ring_submit_common\(\s*ctx,\s*dst_addr,\s*src_addr,\s*byte_len,\s*0u,\s*payload_addr,\s*payload_len,\s*1u,\s*0u,\s*1u,\s*0u\s*\);",
        )
        self.assertRegex(
            impl_text,
            r"void dma_ring_ring_doorbell\(const dma_ring_ctx_t \*ctx\)[\s\S]*?DMA_CSR_RING_DOORBELL",
        )
        nodoorbell = re.search(
            r"int dma_ring_submit_raw_copy_nodoorbell\(dma_ring_ctx_t \*ctx,[\s\S]*?\n\}",
            impl_text,
        )
        self.assertIsNotNone(nodoorbell)
        self.assertNotIn(
            "DMA_CSR_RING_DOORBELL",
            nodoorbell.group(0),
            "staged-fill helper must not ring the doorbell itself",
        )

    def test_irq_helpers_use_contract_csrs_and_ack_in_top_half(self):
        text = DRIVER_C.read_text(encoding="ascii")

        self.assertIn("DMA_CSR_IRQ_ENABLE", text)
        self.assertIn("DMA_CSR_IRQ_STATUS", text)
        self.assertIn("DMA_CSR_IRQ_ACK", text)
        self.assertRegex(
            text,
            r"void dma_ring_irq_enable\(const dma_ring_ctx_t \*ctx\)[\s\S]*?DMA_CSR_IRQ_ENABLE",
        )
        self.assertRegex(
            text,
            r"void dma_ring_irq_ack\(const dma_ring_ctx_t \*ctx\)[\s\S]*?DMA_CSR_IRQ_ACK",
        )
        self.assertRegex(
            text,
            r"void dma_ring_irq_set_coalescing\(const dma_ring_ctx_t \*ctx, uint32_t count_threshold, uint32_t timeout_cycles\)"
            r"[\s\S]*?DMA_CSR_IRQ_COALESCE_COUNT[\s\S]*?DMA_CSR_IRQ_COALESCE_TIMEOUT",
        )
        self.assertRegex(
            text,
            r"uint32_t dma_ring_irq_get_coalesce_count\(const dma_ring_ctx_t \*ctx\)[\s\S]*?DMA_CSR_IRQ_COALESCE_COUNT",
        )
        self.assertRegex(
            text,
            r"uint32_t dma_ring_irq_get_coalesce_timeout\(const dma_ring_ctx_t \*ctx\)[\s\S]*?DMA_CSR_IRQ_COALESCE_TIMEOUT",
        )
        self.assertRegex(
            text,
            r"int dma_ring_irq_top_half\(const dma_ring_ctx_t \*ctx, uint32_t \*status_out\)[\s\S]*?"
            r"status = dma_ring_irq_status\(ctx\);[\s\S]*?dma_ring_irq_ack\(ctx\);",
        )
        top_half = re.search(
            r"int dma_ring_irq_top_half\(const dma_ring_ctx_t \*ctx, uint32_t \*status_out\)([\s\S]*?)\n\}",
            text,
        )
        self.assertIsNotNone(top_half)
        top_half_body = top_half.group(1)
        self.assertNotIn("dma_ring_poll_csw", top_half_body)
        self.assertNotIn("dma_ring_invalidate_result", top_half_body)
        self.assertNotIn("Xil_DCacheInvalidateRange", top_half_body)
        contract_text = CONTRACT_H.read_text(encoding="ascii")
        self.assertIn("DMA_IRQ_DEFAULT_COALESCE_COUNT", contract_text)
        self.assertIn("DMA_IRQ_DEFAULT_COALESCE_TIMEOUT_CYCLES", contract_text)

    def test_actual_len_is_treated_as_descriptor_completion_metadata(self):
        text = DRIVER_C.read_text(encoding="ascii")

        self.assertIn("DMA_DESC_ACTUAL_LEN_BYTE_OFFSET", text)
        self.assertIn("dma_ring_desc_actual_len_ptr", text)
        self.assertIn("desc->actual_len = 0u;", text)
        self.assertRegex(
            text,
            r"uint32_t dma_ring_read_actual_len\(volatile dma_ring_desc_t \*desc\)[\s\S]*?"
            r"dma_ring_invalidate_desc\(desc\);[\s\S]*?return \*dma_ring_desc_actual_len_ptr\(desc\);",
        )
        self.assertNotIn("desc->reserved1", text)

    def test_stream_submit_helper_programs_capacity_and_tlast_bit(self):
        header_text = DRIVER_H.read_text(encoding="ascii")
        impl_text = DRIVER_C.read_text(encoding="ascii")

        self.assertIn("dma_ring_submit_stream", header_text)
        self.assertRegex(
            impl_text,
            r"int dma_ring_submit_stream\(dma_ring_ctx_t \*ctx,\s*"
            r"uint32_t dst_addr,\s*"
            r"uint32_t buffer_capacity,\s*"
            r"const void \*payload_addr,\s*"
            r"uint32_t payload_len\)",
        )
        self.assertIn("DMA_DESC_CTRL_STREAM_TLAST", impl_text)
        self.assertRegex(
            impl_text,
            r"desc->ctrl_len_algo\s*=\s*DMA_DESC_CTRL_STREAM_TLAST\s*\|\s*\(byte_len & DMA_DESC_CTRL_MASK_LEN\);",
        )
        self.assertRegex(
            impl_text,
            r"return dma_ring_submit_common\(\s*ctx,\s*dst_addr,\s*0u,\s*buffer_capacity,\s*0u,\s*payload_addr,\s*payload_len,\s*0u,\s*1u,\s*1u,\s*1u\s*\);",
        )


if __name__ == "__main__":
    unittest.main()
