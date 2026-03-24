#ifndef DMA_MVP_PS_DRIVER_REF_H
#define DMA_MVP_PS_DRIVER_REF_H

#include <stdint.h>

#define DMA_CSR_CTRL           0x00u
#define DMA_CSR_STATUS         0x04u
#define DMA_CSR_KEY0           0x28u
#define DMA_CSR_KEY1           0x2Cu
#define DMA_CSR_KEY2           0x30u
#define DMA_CSR_KEY3           0x34u
#define DMA_CSR_CACHE_CTRL     0x40u
#define DMA_CSR_LOOPBACK_MODE  0x48u
#define DMA_CSR_RING_DOORBELL  0x4Cu
#define DMA_CSR_RING_BASE      0x50u
#define DMA_CSR_RING_HW_HEAD   0x54u
#define DMA_CSR_RING_SW_TAIL   0x58u
#define DMA_CSR_RING_SIZE      0x5Cu
#define DMA_CSR_NET_CFG0       0x90u
#define DMA_CSR_INJ_CTRL       0xA0u
#define DMA_CSR_INJ_DATA       0xA4u
#define DMA_CSR_INJ_STATUS     0xA8u

#define DMA_CTRL_HW_INIT       (1u << 1)
#define DMA_CTRL_ALGO_SM4      (1u << 2)
#define DMA_CTRL_ENCRYPT       (1u << 3)

#define DMA_NET_CFG_ENABLE           (1u << 0)
#define DMA_NET_CFG_INGRESS_INJECT   (1u << 1)
#define DMA_NET_CFG_ARP_ENABLE       (1u << 2)

#define DMA_DESC_CTRL_ALGO_BIT 31u
#define DMA_DESC_CTRL_LEN_MASK 0x00FFFFFFu
#define DMA_DESC_CSW_OWNER     (1u << 31)
#define DMA_DESC_CSW_DONE      (1u << 30)
#define DMA_DESC_CSW_ERR       (1u << 29)
#define DMA_DESC_CSW_STS_MASK  0x00000003u

typedef struct {
    uint32_t dst_addr;
    uint32_t src_addr;
    uint32_t ctrl_len_algo;
    uint32_t reserved0;
    uint32_t csw;
    uint32_t reserved1;
    uint32_t reserved2;
    uint32_t reserved3;
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
                    uint32_t dst_addr,
                    uint32_t byte_len,
                    uint8_t algo_sel,
                    const void *payload_addr,
                    uint32_t payload_len);

int dma_ring_poll_csw(volatile dma_ring_desc_t *desc, uint32_t *csw_out);

void dma_ring_invalidate_result(void *result_addr, uint32_t result_len);

#endif
