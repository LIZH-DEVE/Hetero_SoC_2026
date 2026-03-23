#include "dma_mvp_ps_driver_ref.h"

#include "xil_cache.h"
#include "xil_io.h"

static void dma_ring_flush_desc_and_payload(const dma_ring_desc_t *desc,
                                            const void *payload_addr,
                                            uint32_t payload_len)
{
    Xil_DCacheFlushRange((INTPTR)desc, sizeof(*desc));
    if (payload_addr != 0 && payload_len != 0) {
        Xil_DCacheFlushRange((INTPTR)payload_addr, payload_len);
    }
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
                    uint32_t src_addr,
                    uint32_t byte_len,
                    uint8_t algo_sel,
                    const void *payload_addr,
                    uint32_t payload_len)
{
    dma_ring_desc_t *desc;
    uint16_t next_tail;

    if (ctx == 0 || ctx->ring_base == 0 || ctx->ring_size == 0) {
        return -1;
    }
    if ((byte_len == 0) || ((byte_len & 0xF) != 0)) {
        return -2;
    }

    desc = &ctx->ring_base[ctx->sw_tail];
    desc->src_addr = src_addr;
    desc->ctrl_len_algo = ((uint32_t)(algo_sel & 0x1u) << 31) | (byte_len & 0x00FFFFFFu);
    desc->reserved0 = 0;
    desc->reserved1 = 0;

    dma_ring_flush_desc_and_payload(desc, payload_addr, payload_len);

    next_tail = (uint16_t)((ctx->sw_tail + 1u) % ctx->ring_size);
    ctx->sw_tail = next_tail;

    // HP-port coherency contract:
    //   1. Flush descriptor and payload to DDR.
    //   2. DATA_SYNC to guarantee cache writeback completion before MMIO.
    //   3. Publish software tail through CSR.
    //   4. DATA_SYNC to order the tail write before the doorbell.
    //   5. Ring the doorbell MMIO to wake the fetcher.
    DATA_SYNC;
    Xil_Out32((UINTPTR)(ctx->csr_base + DMA_CSR_RING_SW_TAIL), ctx->sw_tail);
    DATA_SYNC;
    Xil_Out32((UINTPTR)(ctx->csr_base + DMA_CSR_RING_DOORBELL), 1u);

    return 0;
}

void dma_ring_invalidate_result(void *result_addr, uint32_t result_len)
{
    if (result_addr != 0 && result_len != 0) {
        Xil_DCacheInvalidateRange((INTPTR)result_addr, result_len);
    }
}
