#include <stdint.h>
#include <string.h>

#include "xil_printf.h"
#include "xstatus.h"
#include "xparameters.h"
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

#define INVALIDATE_COMPARE_RING_ENTRY_COUNT 2u
#define INVALIDATE_COMPARE_RAW_COPY_BYTES (DMA_RAW_COPY_LEN_MULTIPLE * 2u)
#define POLL_TIMEOUT_ITERS 2000000u

typedef struct {
    dma_ring_desc_t ring[INVALIDATE_COMPARE_RING_ENTRY_COUNT];
    uint8_t guard[DMA_CACHELINE_BYTES];
} dma_desc_region_t;

typedef struct {
    uint8_t bytes[INVALIDATE_COMPARE_RAW_COPY_BYTES];
    uint8_t guard[DMA_CACHELINE_BYTES];
} dma_buffer_region_t;

static dma_desc_region_t g_desc_region
    __attribute__((aligned(DMA_ALIGNMENT_BYTES), section(".dma_desc_region")));
static dma_buffer_region_t g_src_region
    __attribute__((aligned(DMA_ALIGNMENT_BYTES), section(".dma_src_region")));
static dma_buffer_region_t g_dst_region
    __attribute__((aligned(DMA_ALIGNMENT_BYTES), section(".dma_dst_region")));

static dma_ring_desc_t *const g_ring = &g_desc_region.ring[0];
static uint8_t *const g_src_buffer = g_src_region.bytes;
static uint8_t *const g_dst_buffer = g_dst_region.bytes;
static XUartPs g_uart;

static void busy_wait(void)
{
    volatile unsigned long delay = 0U;

    for (delay = 0U; delay < 50000000UL; ++delay) {
    }
}

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

static void seed_raw_copy_buffers(void)
{
    uint32_t i;

    for (i = 0; i < INVALIDATE_COMPARE_RAW_COPY_BYTES; ++i) {
        g_src_buffer[i] = (uint8_t)(0x40u + i);
        g_dst_buffer[i] = 0x00u;
    }
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

static int compare_buffers(const uint8_t *lhs, const uint8_t *rhs, uint32_t len)
{
    uint32_t i;

    for (i = 0; i < len; ++i) {
        if (lhs[i] != rhs[i]) {
            return -1;
        }
    }

    return 0;
}

int main(void)
{
    dma_ring_ctx_t ctx;
    int status;
    int rc;
    uint32_t csw = 0u;
    int match;
    unsigned heartbeat = 0U;

    status = uart1_init_115200();
    if (status != XST_SUCCESS) {
        for (;;) {
        }
    }

    clear_regions();
    seed_raw_copy_buffers();

    dma_ring_init(&ctx,
                  DMA_CSR_BASE,
                  g_ring,
                  (uint32_t)(uintptr_t)g_ring,
                  INVALIDATE_COMPARE_RING_ENTRY_COUNT);
    dma_ring_soft_reset(&ctx);
    dma_ring_init(&ctx,
                  DMA_CSR_BASE,
                  g_ring,
                  (uint32_t)(uintptr_t)g_ring,
                  INVALIDATE_COMPARE_RING_ENTRY_COUNT);

    rc = dma_ring_submit_raw_copy(&ctx,
                                  (uint32_t)(uintptr_t)g_dst_buffer,
                                  (uint32_t)(uintptr_t)g_src_buffer,
                                  INVALIDATE_COMPARE_RAW_COPY_BYTES,
                                  g_src_buffer,
                                  INVALIDATE_COMPARE_RAW_COPY_BYTES);
    if (rc != 0) {
        xil_printf("RAWCOPY_INVALIDATE_COMPARE_FAIL submit_rc=%d\r\n", rc);
        return 1;
    }

    rc = wait_for_csw(g_ring, &csw);
    if (rc != 0) {
        xil_printf("RAWCOPY_INVALIDATE_COMPARE_FAIL wait_rc=%d csw=0x%08x\r\n",
                   rc,
                   (unsigned int)csw);
        return 2;
    }

    xil_printf("RAWCOPY INVALIDATE COMPARE DIAG\r\n");
    xil_printf("RAWCOPY_INVALIDATE_COMPARE_STAGE WAIT_DONE csw=0x%08x\r\n",
               (unsigned int)csw);
    xil_printf("RAWCOPY_INVALIDATE_COMPARE_STAGE BEFORE_INVALIDATE\r\n");

    dma_ring_invalidate_result(g_dst_buffer, INVALIDATE_COMPARE_RAW_COPY_BYTES);
    match = (compare_buffers(g_src_buffer, g_dst_buffer, INVALIDATE_COMPARE_RAW_COPY_BYTES) == 0) ? 1 : 0;

    xil_printf("RAWCOPY_INVALIDATE_COMPARE_STAGE AFTER_COMPARE match=%d\r\n",
               match);
    if (match == 0) {
        xil_printf("RAWCOPY_INVALIDATE_COMPARE_FAIL\r\n");
        return 3;
    }

    xil_printf("RAWCOPY_INVALIDATE_COMPARE_OK\r\n");

    for (;;) {
        busy_wait();
        xil_printf("RAWCOPY_INVALIDATE_COMPARE_HEARTBEAT %u\r\n", heartbeat++);
    }
}
