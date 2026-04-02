#include "dma_mvp_ps_driver_ref.h"

#include "xil_cache.h"
#include "xil_io.h"

static volatile uint32_t *dma_ring_desc_actual_len_ptr(volatile dma_ring_desc_t *desc)
{
    return (volatile uint32_t *)((volatile uint8_t *)desc + DMA_DESC_ACTUAL_LEN_BYTE_OFFSET);
}

static void dma_ring_flush_desc_and_payload(const dma_ring_desc_t *desc,
                                            const void *payload_addr,
                                            uint32_t payload_len)
{
    Xil_DCacheFlushRange((INTPTR)desc, sizeof(*desc));
    if (payload_addr != 0 && payload_len != 0) {
        Xil_DCacheFlushRange((INTPTR)payload_addr, payload_len);
    }
}

static void dma_ring_invalidate_desc(const volatile dma_ring_desc_t *desc)
{
    if (desc != 0) {
        Xil_DCacheInvalidateRange((INTPTR)desc, sizeof(*desc));
        DATA_SYNC;
    }
}

uint16_t dma_ring_get_hw_head(const dma_ring_ctx_t *ctx)
{
    if (ctx == 0) {
        return 0u;
    }

    return (uint16_t)(Xil_In32((UINTPTR)(ctx->csr_base + DMA_CSR_RING_HW_HEAD)) & 0xFFFFu);
}

uint16_t dma_ring_get_free_slots(const dma_ring_ctx_t *ctx)
{
    uint16_t hw_head;
    uint16_t used;

    if (ctx == 0 || ctx->ring_size < 2u) {
        return 0u;
    }

    hw_head = dma_ring_get_hw_head(ctx);
    if (ctx->sw_tail >= hw_head) {
        used = (uint16_t)(ctx->sw_tail - hw_head);
    } else {
        used = (uint16_t)((uint16_t)(ctx->ring_size - hw_head) + ctx->sw_tail);
    }

    return (uint16_t)(ctx->ring_size - used - 1u);
}

static int dma_ring_submit_common(dma_ring_ctx_t *ctx,
                                  uint32_t dst_addr,
                                  uint32_t src_addr,
                                  uint32_t byte_len,
                                  uint8_t algo_sel,
                                  const void *payload_addr,
                                  uint32_t payload_len,
                                  uint8_t raw_copy_mode,
                                  uint8_t stream_mode,
                                  uint8_t publish_tail,
                                  uint8_t ring_doorbell)
{
    dma_ring_desc_t *desc;
    uint16_t hw_head;
    uint16_t next_tail;

    if (ctx == 0 || ctx->ring_base == 0 || ctx->ring_size < 2u) {
        return -1;
    }
    if ((byte_len == 0u) || ((byte_len & (DMA_DESC_WORD_BYTES - 1u)) != 0u)) {
        return -2;
    }
    if (raw_copy_mode && !stream_mode && ((byte_len & (DMA_RAW_COPY_LEN_MULTIPLE - 1u)) != 0u)) {
        return -2;
    }
    if (!raw_copy_mode && !stream_mode && ((byte_len & (16u - 1u)) != 0u)) {
        return -2;
    }
    if ((dst_addr & (DMA_ALIGNMENT_BYTES - 1u)) != 0u) {
        return -3;
    }
    if (raw_copy_mode && ((src_addr & (DMA_ALIGNMENT_BYTES - 1u)) != 0u)) {
        return -4;
    }
    if (!stream_mode && ((uint32_t)(uintptr_t)payload_addr & (DMA_ALIGNMENT_BYTES - 1u)) != 0u) {
        return -6;
    }

    hw_head = dma_ring_get_hw_head(ctx);
    next_tail = (uint16_t)((ctx->sw_tail + 1u) % ctx->ring_size);
    if (next_tail == hw_head) {
        return -5;
    }

    desc = &ctx->ring_base[ctx->sw_tail];
    desc->dst_addr = dst_addr;
    desc->src_addr = raw_copy_mode ? src_addr : ((payload_addr != 0) ? (uint32_t)(uintptr_t)payload_addr : 0u);
    if (raw_copy_mode) {
        desc->ctrl_len_algo = byte_len & DMA_DESC_CTRL_MASK_LEN;
    } else if (stream_mode) {
        desc->ctrl_len_algo = DMA_DESC_CTRL_STREAM_TLAST | (byte_len & DMA_DESC_CTRL_MASK_LEN);
    } else {
        desc->ctrl_len_algo = ((uint32_t)(algo_sel & 0x1u) << DMA_DESC_CTRL_BIT_ALGO) |
                              (byte_len & DMA_DESC_CTRL_MASK_LEN);
    }
    desc->reserved0 = 0;
    desc->csw = DMA_DESC_CSW_OWNER;
    desc->actual_len = 0u;
    desc->reserved2 = 0;
    desc->reserved3 = 0;

    dma_ring_flush_desc_and_payload(desc, payload_addr, payload_len);

    ctx->sw_tail = next_tail;

    DATA_SYNC;
    if (publish_tail != 0u) {
        Xil_Out32((UINTPTR)(ctx->csr_base + DMA_CSR_RING_SW_TAIL), ctx->sw_tail);
        DATA_SYNC;
    }
    if (ring_doorbell != 0u) {
        Xil_Out32((UINTPTR)(ctx->csr_base + DMA_CSR_RING_DOORBELL), 1u);
        DATA_SYNC;
    }

    return 0;
}

void dma_ring_init(dma_ring_ctx_t *ctx,
                   uintptr_t csr_base,
                   dma_ring_desc_t *ring_base,
                   uint32_t ring_base_phys,
                   uint16_t ring_size)
{
    ctx->csr_base = csr_base;
    ctx->ring_base = ring_base;
    ctx->ring_base_phys = ring_base_phys;
    ctx->ring_size = ring_size;
    ctx->sw_tail = 0;

    Xil_Out32((UINTPTR)(csr_base + DMA_CSR_RING_BASE), ring_base_phys);
    Xil_Out32((UINTPTR)(csr_base + DMA_CSR_RING_SIZE), ring_size);
    Xil_Out32((UINTPTR)(csr_base + DMA_CSR_RING_SW_TAIL), 0);
}

int dma_ring_submit(dma_ring_ctx_t *ctx,
                    uint32_t dst_addr,
                    uint32_t byte_len,
                    uint8_t algo_sel,
                    const void *payload_addr,
                    uint32_t payload_len)
{
    return dma_ring_submit_common(ctx,
                                  dst_addr,
                                  0u,
                                  byte_len,
                                  algo_sel,
                                  payload_addr,
                                  payload_len,
                                  0u,
                                  0u,
                                  1u,
                                  1u);
}

int dma_ring_submit_nodoorbell(dma_ring_ctx_t *ctx,
                               uint32_t dst_addr,
                               uint32_t byte_len,
                               uint8_t algo_sel,
                               const void *payload_addr,
                               uint32_t payload_len)
{
    return dma_ring_submit_common(ctx,
                                  dst_addr,
                                  0u,
                                  byte_len,
                                  algo_sel,
                                  payload_addr,
                                  payload_len,
                                  0u,
                                  0u,
                                  0u,
                                  0u);
}

int dma_ring_submit_raw_copy(dma_ring_ctx_t *ctx,
                             uint32_t dst_addr,
                             uint32_t src_addr,
                             uint32_t byte_len,
                             const void *payload_addr,
                             uint32_t payload_len)
{
    return dma_ring_submit_common(ctx,
                                  dst_addr,
                                  src_addr,
                                  byte_len,
                                  0u,
                                  payload_addr,
                                  payload_len,
                                  1u,
                                  0u,
                                  1u,
                                  1u);
}

int dma_ring_submit_raw_copy_nodoorbell(dma_ring_ctx_t *ctx,
                                        uint32_t dst_addr,
                                        uint32_t src_addr,
                                        uint32_t byte_len,
                                        const void *payload_addr,
                                        uint32_t payload_len)
{
    return dma_ring_submit_common(ctx,
                                  dst_addr,
                                  src_addr,
                                  byte_len,
                                  0u,
                                  payload_addr,
                                  payload_len,
                                  1u,
                                  0u,
                                  1u,
                                  0u);
}

int dma_ring_submit_stream(dma_ring_ctx_t *ctx,
                           uint32_t dst_addr,
                           uint32_t buffer_capacity,
                           const void *payload_addr,
                           uint32_t payload_len)
{
    return dma_ring_submit_common(ctx,
                                  dst_addr,
                                  0u,
                                  buffer_capacity,
                                  0u,
                                  payload_addr,
                                  payload_len,
                                  0u,
                                  1u,
                                  1u,
                                  1u);
}

void dma_ring_soft_reset(const dma_ring_ctx_t *ctx)
{
    if (ctx != 0) {
        Xil_Out32((UINTPTR)(ctx->csr_base + DMA_CSR_CTRL), DMA_CTRL_SOFT_RESET);
        DATA_SYNC;
        Xil_Out32((UINTPTR)(ctx->csr_base + DMA_CSR_CTRL), 0u);
        DATA_SYNC;
    }
}

void dma_ring_ring_doorbell(const dma_ring_ctx_t *ctx)
{
    if (ctx != 0) {
        DATA_SYNC;
        Xil_Out32((UINTPTR)(ctx->csr_base + DMA_CSR_RING_DOORBELL), 1u);
        DATA_SYNC;
    }
}

int dma_ring_publish_tail(const dma_ring_ctx_t *ctx)
{
    if (ctx == 0) {
        return -1;
    }

    DATA_SYNC;
    Xil_Out32((UINTPTR)(ctx->csr_base + DMA_CSR_RING_SW_TAIL), ctx->sw_tail);
    DATA_SYNC;
    return 0;
}

int dma_ring_submit_batch(dma_ring_ctx_t *ctx,
                          const dma_ring_submit_spec_t *specs,
                          uint32_t count)
{
    uint32_t idx;
    int rc;

    if (ctx == 0 || specs == 0 || count == 0u) {
        return -1;
    }

    for (idx = 0u; idx < count; ++idx) {
        const dma_ring_submit_spec_t *spec = &specs[idx];
        rc = dma_ring_submit_common(ctx,
                                    spec->dst_addr,
                                    spec->src_addr,
                                    spec->byte_len,
                                    spec->algo_sel,
                                    spec->payload_addr,
                                    spec->payload_len,
                                    spec->raw_copy_mode,
                                    spec->stream_mode,
                                    0u,
                                    0u);
        if (rc != 0) {
            return rc;
        }
    }

    rc = dma_ring_publish_tail(ctx);
    if (rc != 0) {
        return rc;
    }

    dma_ring_ring_doorbell(ctx);
    return 0;
}

void dma_ring_irq_enable(const dma_ring_ctx_t *ctx)
{
    if (ctx != 0) {
        Xil_Out32((UINTPTR)(ctx->csr_base + DMA_CSR_IRQ_ENABLE), DMA_IRQ_ENABLE_DONE);
        DATA_SYNC;
    }
}

void dma_ring_irq_disable(const dma_ring_ctx_t *ctx)
{
    if (ctx != 0) {
        Xil_Out32((UINTPTR)(ctx->csr_base + DMA_CSR_IRQ_ENABLE), 0u);
        DATA_SYNC;
    }
}

void dma_ring_irq_set_coalescing(const dma_ring_ctx_t *ctx, uint32_t count_threshold, uint32_t timeout_cycles)
{
    if (ctx != 0) {
        Xil_Out32((UINTPTR)(ctx->csr_base + DMA_CSR_IRQ_COALESCE_COUNT), count_threshold);
        Xil_Out32((UINTPTR)(ctx->csr_base + DMA_CSR_IRQ_COALESCE_TIMEOUT), timeout_cycles);
        DATA_SYNC;
    }
}

uint32_t dma_ring_irq_get_coalesce_count(const dma_ring_ctx_t *ctx)
{
    if (ctx == 0) {
        return 0u;
    }

    return Xil_In32((UINTPTR)(ctx->csr_base + DMA_CSR_IRQ_COALESCE_COUNT));
}

uint32_t dma_ring_irq_get_coalesce_timeout(const dma_ring_ctx_t *ctx)
{
    if (ctx == 0) {
        return 0u;
    }

    return Xil_In32((UINTPTR)(ctx->csr_base + DMA_CSR_IRQ_COALESCE_TIMEOUT));
}

uint32_t dma_ring_irq_status(const dma_ring_ctx_t *ctx)
{
    if (ctx == 0) {
        return 0u;
    }

    return Xil_In32((UINTPTR)(ctx->csr_base + DMA_CSR_IRQ_STATUS));
}

void dma_ring_irq_ack(const dma_ring_ctx_t *ctx)
{
    if (ctx != 0) {
        Xil_Out32((UINTPTR)(ctx->csr_base + DMA_CSR_IRQ_ACK), DMA_IRQ_ACK_DONE_ACK);
        DATA_SYNC;
    }
}

int dma_ring_irq_top_half(const dma_ring_ctx_t *ctx, uint32_t *status_out)
{
    uint32_t status;

    if (ctx == 0) {
        return -1;
    }

    status = dma_ring_irq_status(ctx);
    if (status_out != 0) {
        *status_out = status;
    }
    if ((status & DMA_IRQ_STATUS_DONE_PENDING) == 0u) {
        return 0;
    }

    dma_ring_irq_ack(ctx);
    return 1;
}

int dma_ring_poll_csw(volatile dma_ring_desc_t *desc, uint32_t *csw_out)
{
    uint32_t csw;

    if (desc == 0) {
        return -1;
    }

    dma_ring_invalidate_desc(desc);
    csw = desc->csw;
    if (csw_out != 0) {
        *csw_out = csw;
    }

    if ((csw & DMA_DESC_CSW_OWNER) != 0u) {
        return 1;
    }
    if ((csw & DMA_DESC_CSW_DONE) == 0u) {
        return 1;
    }
    if ((csw & DMA_DESC_CSW_ERR) != 0u) {
        return -2;
    }

    return 0;
}

uint32_t dma_ring_read_actual_len(volatile dma_ring_desc_t *desc)
{
    if (desc == 0) {
        return 0u;
    }

    dma_ring_invalidate_desc(desc);
    return *dma_ring_desc_actual_len_ptr(desc);
}

void dma_ring_invalidate_result(void *result_addr, uint32_t result_len)
{
    if (result_addr != 0 && result_len != 0) {
        Xil_DCacheInvalidateRange((INTPTR)result_addr, result_len);
        DATA_SYNC;
    }
}
