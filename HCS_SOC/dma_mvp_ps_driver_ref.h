#ifndef DMA_MVP_PS_DRIVER_REF_H
#define DMA_MVP_PS_DRIVER_REF_H

#include <stdint.h>
#include "dma_hw_regs.h"

typedef dma_desc_t dma_ring_desc_t;

typedef struct {
    uintptr_t csr_base;
    dma_ring_desc_t *ring_base;
    uint32_t ring_base_phys;
    uint16_t ring_size;
    uint16_t sw_tail;
} dma_ring_ctx_t;

typedef struct {
    uint32_t dst_addr;
    uint32_t src_addr;
    uint32_t byte_len;
    uint8_t algo_sel;
    const void *payload_addr;
    uint32_t payload_len;
    uint8_t raw_copy_mode;
    uint8_t stream_mode;
} dma_ring_submit_spec_t;

uint16_t dma_ring_get_hw_head(const dma_ring_ctx_t *ctx);
uint16_t dma_ring_get_free_slots(const dma_ring_ctx_t *ctx);

void dma_ring_init(dma_ring_ctx_t *ctx,
                   uintptr_t csr_base,
                   dma_ring_desc_t *ring_base,
                   uint32_t ring_base_phys,
                   uint16_t ring_size);

int dma_ring_submit(dma_ring_ctx_t *ctx,
                    uint32_t dst_addr,
                    uint32_t byte_len,
                    uint8_t algo_sel,
                    const void *payload_addr,
                    uint32_t payload_len);

int dma_ring_submit_nodoorbell(dma_ring_ctx_t *ctx,
                               uint32_t dst_addr,
                               uint32_t byte_len,
                               uint8_t algo_sel,
                               const void *payload_addr,
                               uint32_t payload_len);

int dma_ring_submit_raw_copy(dma_ring_ctx_t *ctx,
                             uint32_t dst_addr,
                             uint32_t src_addr,
                             uint32_t byte_len,
                             const void *payload_addr,
                             uint32_t payload_len);

int dma_ring_submit_raw_copy_nodoorbell(dma_ring_ctx_t *ctx,
                                        uint32_t dst_addr,
                                        uint32_t src_addr,
                                        uint32_t byte_len,
                                        const void *payload_addr,
                                        uint32_t payload_len);

int dma_ring_submit_stream(dma_ring_ctx_t *ctx,
                           uint32_t dst_addr,
                           uint32_t buffer_capacity,
                           const void *payload_addr,
                           uint32_t payload_len);

int dma_ring_publish_tail(const dma_ring_ctx_t *ctx);
int dma_ring_submit_batch(dma_ring_ctx_t *ctx,
                          const dma_ring_submit_spec_t *specs,
                          uint32_t count);

void dma_ring_soft_reset(const dma_ring_ctx_t *ctx);
void dma_ring_ring_doorbell(const dma_ring_ctx_t *ctx);

void dma_ring_irq_enable(const dma_ring_ctx_t *ctx);
void dma_ring_irq_disable(const dma_ring_ctx_t *ctx);
void dma_ring_irq_set_coalescing(const dma_ring_ctx_t *ctx, uint32_t count_threshold, uint32_t timeout_cycles);
uint32_t dma_ring_irq_get_coalesce_count(const dma_ring_ctx_t *ctx);
uint32_t dma_ring_irq_get_coalesce_timeout(const dma_ring_ctx_t *ctx);
uint32_t dma_ring_irq_status(const dma_ring_ctx_t *ctx);
void dma_ring_irq_ack(const dma_ring_ctx_t *ctx);
int dma_ring_irq_top_half(const dma_ring_ctx_t *ctx, uint32_t *status_out);

int dma_ring_poll_csw(volatile dma_ring_desc_t *desc, uint32_t *csw_out);
uint32_t dma_ring_read_actual_len(volatile dma_ring_desc_t *desc);

void dma_ring_invalidate_result(void *result_addr, uint32_t result_len);

#endif
