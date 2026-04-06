#include <stdint.h>
#include <string.h>

#include "xparameters.h"
#include "xstatus.h"
#include "xil_printf.h"
#include "xuartps.h"

#include "dma_hw_regs.h"
#include "dma_mvp_ps_driver_ref.h"

#if defined(XPAR_DMA_RAW_COPY_SUBSYSTEM_0_BASEADDR)
#define DMA_CSR_BASE XPAR_DMA_RAW_COPY_SUBSYSTEM_0_BASEADDR
#elif defined(XPAR_DMA_RAW_COPY_SUBSYSTEM_0_S_AXIL_BASEADDR)
#define DMA_CSR_BASE XPAR_DMA_RAW_COPY_SUBSYSTEM_0_S_AXIL_BASEADDR
#else
#error "No DMA raw-copy CSR base address found in xparameters.h"
#endif

#define MVP_RING_ENTRY_COUNT 4u
#define MVP_DESC_COUNT 3u
#define MVP_COPY_BYTES (DMA_RAW_COPY_LEN_MULTIPLE * 2u)
#define POLL_TIMEOUT_ITERS 3000000u
#define IRQ_TIMEOUT_ITERS 3000000u
#define MVP_IRQ_COALESCE_COUNT 2u
#define MVP_IRQ_COALESCE_TIMEOUT 64u

typedef struct {
    dma_ring_desc_t ring[MVP_RING_ENTRY_COUNT];
    uint8_t guard[DMA_CACHELINE_BYTES];
} dma_desc_region_t;

typedef struct {
    uint8_t bytes[MVP_COPY_BYTES];
    uint8_t guard[DMA_CACHELINE_BYTES];
} dma_buffer_region_t;

static dma_desc_region_t g_desc_region
    __attribute__((aligned(DMA_ALIGNMENT_BYTES), section(".dma_desc_region")));
static dma_buffer_region_t g_src_region[MVP_DESC_COUNT]
    __attribute__((aligned(DMA_ALIGNMENT_BYTES), section(".dma_src_region")));
static dma_buffer_region_t g_dst_region[MVP_DESC_COUNT]
    __attribute__((aligned(DMA_ALIGNMENT_BYTES), section(".dma_dst_region")));

static dma_ring_desc_t *const g_ring = &g_desc_region.ring[0];
static XUartPs g_uart;

static int uart1_init_115200(void)
{
    XUartPs_Config *config;
    int status;

    config = XUartPs_LookupConfig(XPAR_XUARTPS_0_DEVICE_ID);
    if (config == NULL) {
        return XST_FAILURE;
    }

    status = XUartPs_CfgInitialize(&g_uart, config, config->BaseAddress);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = XUartPs_SetBaudRate(&g_uart, 115200U);
    if (status != XST_SUCCESS) {
        return status;
    }

    return XST_SUCCESS;
}

static void clear_regions(void)
{
    memset(&g_desc_region, 0, sizeof(g_desc_region));
    memset(&g_src_region, 0, sizeof(g_src_region));
    memset(&g_dst_region, 0, sizeof(g_dst_region));
}

static void seed_raw_copy_buffers(uint8_t phase_tag)
{
    uint32_t desc_idx;
    uint32_t byte_idx;

    for (desc_idx = 0; desc_idx < MVP_DESC_COUNT; ++desc_idx) {
        for (byte_idx = 0; byte_idx < MVP_COPY_BYTES; ++byte_idx) {
            g_src_region[desc_idx].bytes[byte_idx] =
                (uint8_t)(phase_tag + (uint8_t)(desc_idx * 0x20u) + (uint8_t)byte_idx);
            g_dst_region[desc_idx].bytes[byte_idx] = 0u;
        }
    }
}

static int compare_buffers(uint32_t index)
{
    uint32_t i;
    const uint8_t *lhs = g_src_region[index].bytes;
    const uint8_t *rhs = g_dst_region[index].bytes;

    for (i = 0; i < MVP_COPY_BYTES; ++i) {
        if (lhs[i] != rhs[i]) {
            xil_printf("  mismatch[%u][%u]: got=0x%02x exp=0x%02x\r\n",
                       (unsigned int)index,
                       (unsigned int)i,
                       (unsigned int)rhs[i],
                       (unsigned int)lhs[i]);
            return -1;
        }
    }

    return 0;
}

static int wait_for_csw(volatile dma_ring_desc_t *desc, uint32_t *csw_out)
{
    uint32_t i;

    for (i = 0; i < POLL_TIMEOUT_ITERS; ++i) {
        int rc = dma_ring_poll_csw(desc, csw_out);
        if (rc <= 0) {
            return rc;
        }
    }

    return -3;
}

static int wait_for_irq_event(const dma_ring_ctx_t *ctx, uint32_t *status_out)
{
    uint32_t i;

    for (i = 0; i < IRQ_TIMEOUT_ITERS; ++i) {
        int rc = dma_ring_irq_top_half(ctx, status_out);
        if (rc != 0) {
            return rc;
        }
    }

    return -3;
}

static int validate_completed_desc(uint32_t index)
{
    uint32_t csw = 0u;
    uint32_t actual_len;
    int rc;

    rc = wait_for_csw(&g_ring[index], &csw);
    if (rc != 0) {
        xil_printf("MVP_DESC[%u] poll failed rc=%d csw=0x%08x\r\n",
                   (unsigned int)index,
                   rc,
                   (unsigned int)csw);
        return -1;
    }

    actual_len = dma_ring_read_actual_len(&g_ring[index]);
    xil_printf("MVP_DESC[%u] done csw=0x%08x actual_len=%u\r\n",
               (unsigned int)index,
               (unsigned int)csw,
               (unsigned int)actual_len);
    if (actual_len != MVP_COPY_BYTES) {
        xil_printf("MVP_DESC[%u] actual_len mismatch\r\n", (unsigned int)index);
        return -2;
    }

    dma_ring_invalidate_result(g_dst_region[index].bytes, MVP_COPY_BYTES);
    if (compare_buffers(index) != 0) {
        xil_printf("MVP_DESC[%u] payload compare failed\r\n", (unsigned int)index);
        return -3;
    }

    return 0;
}

static void prepare_ring(dma_ring_ctx_t *ctx)
{
    dma_ring_init(ctx,
                  DMA_CSR_BASE,
                  g_ring,
                  (uint32_t)(uintptr_t)g_ring,
                  MVP_RING_ENTRY_COUNT);
    dma_ring_soft_reset(ctx);
    dma_ring_init(ctx,
                  DMA_CSR_BASE,
                  g_ring,
                  (uint32_t)(uintptr_t)g_ring,
                  MVP_RING_ENTRY_COUNT);
}

static int run_ring_full_phase(dma_ring_ctx_t *ctx)
{
    uint32_t index;
    uint32_t hw_head;
    uint16_t free_slots;
    int rc;

    clear_regions();
    seed_raw_copy_buffers(0x40u);
    prepare_ring(ctx);

    xil_printf("MVP_STAGE RING_FILL_QUIESCED\r\n");
    for (index = 0; index < MVP_DESC_COUNT; ++index) {
        rc = dma_ring_submit_raw_copy_nodoorbell(ctx,
                                                 (uint32_t)(uintptr_t)g_dst_region[index].bytes,
                                                 (uint32_t)(uintptr_t)g_src_region[index].bytes,
                                                 MVP_COPY_BYTES,
                                                 g_src_region[index].bytes,
                                                 MVP_COPY_BYTES);
        xil_printf("  submit rc[%u]=%d sw_tail=%u\r\n",
                   (unsigned int)index,
                   rc,
                   (unsigned int)ctx->sw_tail);
        if (rc != 0) {
            return -10 - (int)index;
        }
    }

    rc = dma_ring_submit_raw_copy_nodoorbell(ctx,
                                             (uint32_t)(uintptr_t)g_dst_region[0].bytes,
                                             (uint32_t)(uintptr_t)g_src_region[0].bytes,
                                             MVP_COPY_BYTES,
                                             g_src_region[0].bytes,
                                             MVP_COPY_BYTES);
    hw_head = dma_ring_get_hw_head(ctx);
    free_slots = dma_ring_get_free_slots(ctx);
    xil_printf("MVP_STAGE RING_FULL_CHECK submit rc[3]=%d sw_tail=%u hw_head=%u free_slots=%u\r\n",
               rc,
               (unsigned int)ctx->sw_tail,
               (unsigned int)hw_head,
               (unsigned int)free_slots);
    if (rc != -5) {
        return -20;
    }
    xil_printf("MVP_STAGE RING_FULL_EXPECT submit rc[3]=-5\r\n");
    xil_printf("MVP_STAGE RING_RELEASE\r\n");
    dma_ring_ring_doorbell(ctx);

    for (index = 0; index < MVP_DESC_COUNT; ++index) {
        rc = validate_completed_desc(index);
        if (rc != 0) {
            return -30 - (int)index;
        }
    }

    hw_head = dma_ring_get_hw_head(ctx);
    free_slots = dma_ring_get_free_slots(ctx);
    xil_printf("MVP_STAGE RING_DRAINED hw_head=%u sw_tail=%u free_slots=%u\r\n",
               (unsigned int)hw_head,
               (unsigned int)ctx->sw_tail,
               (unsigned int)free_slots);
    if ((hw_head != ctx->sw_tail) || (free_slots != (MVP_RING_ENTRY_COUNT - 1u))) {
        return -40;
    }

    return 0;
}

static int run_irq_count_phase(dma_ring_ctx_t *ctx)
{
    uint32_t irq_status = 0u;
    uint32_t index;
    int rc;

    clear_regions();
    seed_raw_copy_buffers(0x80u);
    prepare_ring(ctx);

    dma_ring_irq_set_coalescing(ctx, MVP_IRQ_COALESCE_COUNT, MVP_IRQ_COALESCE_TIMEOUT);
    dma_ring_irq_enable(ctx);
    xil_printf("MVP_IRQ_CONFIG count=2 timeout=64\r\n");

    for (index = 0; index < 2u; ++index) {
        rc = dma_ring_submit_raw_copy(ctx,
                                      (uint32_t)(uintptr_t)g_dst_region[index].bytes,
                                      (uint32_t)(uintptr_t)g_src_region[index].bytes,
                                      MVP_COPY_BYTES,
                                      g_src_region[index].bytes,
                                      MVP_COPY_BYTES);
        if (rc != 0) {
            dma_ring_irq_disable(ctx);
            return -50 - (int)index;
        }
    }

    rc = wait_for_irq_event(ctx, &irq_status);
    xil_printf("MVP_IRQ_COUNT status=0x%08x rc=%d\r\n",
               (unsigned int)irq_status,
               rc);
    if ((rc != 1) || ((irq_status & DMA_IRQ_STATUS_DONE_PENDING) == 0u)) {
        dma_ring_irq_disable(ctx);
        return -60;
    }

    for (index = 0; index < 2u; ++index) {
        rc = validate_completed_desc(index);
        if (rc != 0) {
            dma_ring_irq_disable(ctx);
            return -70 - (int)index;
        }
    }

    dma_ring_irq_disable(ctx);
    return 0;
}

static int run_irq_timeout_phase(dma_ring_ctx_t *ctx)
{
    uint32_t irq_status = 0u;
    int rc;

    clear_regions();
    seed_raw_copy_buffers(0xC0u);
    prepare_ring(ctx);

    dma_ring_irq_set_coalescing(ctx, MVP_IRQ_COALESCE_COUNT, MVP_IRQ_COALESCE_TIMEOUT);
    dma_ring_irq_enable(ctx);

    rc = dma_ring_submit_raw_copy(ctx,
                                  (uint32_t)(uintptr_t)g_dst_region[0].bytes,
                                  (uint32_t)(uintptr_t)g_src_region[0].bytes,
                                  MVP_COPY_BYTES,
                                  g_src_region[0].bytes,
                                  MVP_COPY_BYTES);
    if (rc != 0) {
        dma_ring_irq_disable(ctx);
        return -80;
    }

    rc = wait_for_irq_event(ctx, &irq_status);
    xil_printf("MVP_IRQ_TIMEOUT status=0x%08x rc=%d\r\n",
               (unsigned int)irq_status,
               rc);
    if ((rc != 1) || ((irq_status & DMA_IRQ_STATUS_DONE_PENDING) == 0u)) {
        dma_ring_irq_disable(ctx);
        return -90;
    }

    rc = validate_completed_desc(0u);
    dma_ring_irq_disable(ctx);
    if (rc != 0) {
        return -100;
    }

    return 0;
}

int main(void)
{
    dma_ring_ctx_t ctx;
    int rc;

    rc = uart1_init_115200();
    if (rc != XST_SUCCESS) {
        for (;;) {
        }
    }

    xil_printf("DMA raw-copy MVP image\r\n");
    xil_printf("  contract_ver = %u\r\n", (unsigned int)DMA_CONTRACT_VERSION);
    xil_printf("  csr_base     = 0x%08x\r\n", (unsigned int)DMA_CSR_BASE);
    xil_printf("  ring_base    = 0x%08x\r\n", (unsigned int)(uintptr_t)g_ring);
    xil_printf("  ring_size    = %u\r\n", (unsigned int)MVP_RING_ENTRY_COUNT);
    xil_printf("  len          = %u\r\n", (unsigned int)MVP_COPY_BYTES);

    rc = run_ring_full_phase(&ctx);
    if (rc != 0) {
        xil_printf("MVP ring-full phase failed rc=%d\r\n", rc);
        xil_printf("DMA raw-copy MVP FAIL\r\n");
        return 1;
    }

    rc = run_irq_count_phase(&ctx);
    if (rc != 0) {
        xil_printf("MVP IRQ count phase failed rc=%d\r\n", rc);
        xil_printf("DMA raw-copy MVP FAIL\r\n");
        return 2;
    }

    rc = run_irq_timeout_phase(&ctx);
    if (rc != 0) {
        xil_printf("MVP IRQ timeout phase failed rc=%d\r\n", rc);
        xil_printf("DMA raw-copy MVP FAIL\r\n");
        return 3;
    }

    xil_printf("DMA raw-copy MVP PASS\r\n");
    return 0;
}
