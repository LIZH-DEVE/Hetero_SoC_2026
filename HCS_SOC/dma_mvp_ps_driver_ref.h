#ifndef DMA_MVP_PS_DRIVER_REF_H
#define DMA_MVP_PS_DRIVER_REF_H

#include <stdint.h>

#define DMA_CSR_CTRL           0x00u
#define DMA_CSR_STATUS         0x04u
#define DMA_CSR_CACHE_CTRL     0x40u
#define DMA_CSR_LOOPBACK_MODE  0x48u
#define DMA_CSR_RING_DOORBELL  0x4Cu
#define DMA_CSR_RING_BASE      0x50u
#define DMA_CSR_RING_HW_HEAD   0x54u
#define DMA_CSR_RING_SW_TAIL   0x58u
#define DMA_CSR_RING_SIZE      0x5Cu

typedef struct {
    uint32_t src_addr;
    uint32_t ctrl_len_algo;
    uint32_t reserved0;
    uint32_t reserved1;
} dma_ring_desc_t;

typedef struct {
    uintptr_t csr_base;
    dma_ring_desc_t *ring_base;
    uint32_t ring_base_phys;
    uint16_t ring_size;
    uint16_t sw_tail;
} dma_ring_ctx_t;

void dma_ring_init(dma_ring_ctx_t *ctx,
                   uintptr_t csr_base,
                   dma_ring_desc_t *ring_base,
                   uint32_t ring_base_phys,
                   uint16_t ring_size);

int dma_ring_submit(dma_ring_ctx_t *ctx,
                    uint32_t src_addr,
                    uint32_t byte_len,
                    uint8_t algo_sel,
                    const void *payload_addr,
                    uint32_t payload_len);

void dma_ring_invalidate_result(void *result_addr, uint32_t result_len);

#endif
