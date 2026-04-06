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

#define SUBMIT_RING_ENTRY_COUNT 1u
#define SUBMIT_RAW_COPY_BYTES (DMA_RAW_COPY_LEN_MULTIPLE * 2u)

typedef struct {
    dma_ring_desc_t ring[SUBMIT_RING_ENTRY_COUNT];
    uint8_t guard[DMA_CACHELINE_BYTES];
} dma_desc_region_t;

typedef struct {
    uint8_t bytes[SUBMIT_RAW_COPY_BYTES];
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

    for (i = 0; i < SUBMIT_RAW_COPY_BYTES; ++i) {
        g_src_buffer[i] = (uint8_t)(0x40u + i);
        g_dst_buffer[i] = 0x00u;
    }
}

int main(void)
{
    dma_ring_ctx_t ctx;
    int status;
    int rc;
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
                  SUBMIT_RING_ENTRY_COUNT);
    dma_ring_soft_reset(&ctx);
    dma_ring_init(&ctx,
                  DMA_CSR_BASE,
                  g_ring,
                  (uint32_t)(uintptr_t)g_ring,
                  SUBMIT_RING_ENTRY_COUNT);

    xil_printf("RAWCOPY SUBMIT DIAG\r\n");
    xil_printf("RAWCOPY_SUBMIT_STAGE REINIT_DONE csr=0x%08x ring=0x%08x count=%d\r\n",
               (unsigned int)ctx.csr_base,
               (unsigned int)ctx.ring_base_phys,
               (int)ctx.ring_size);
    xil_printf("RAWCOPY_SUBMIT_STAGE BEFORE_SUBMIT\r\n");

    rc = dma_ring_submit_raw_copy(&ctx,
                                  (uint32_t)(uintptr_t)g_dst_buffer,
                                  (uint32_t)(uintptr_t)g_src_buffer,
                                  SUBMIT_RAW_COPY_BYTES,
                                  g_src_buffer,
                                  SUBMIT_RAW_COPY_BYTES);

    xil_printf("RAWCOPY_SUBMIT_STAGE AFTER_SUBMIT rc=%d sw_tail=%d\r\n",
               rc,
               (int)ctx.sw_tail);

    if (rc != 0) {
        xil_printf("RAWCOPY_SUBMIT_FAIL\r\n");
        return 1;
    }

    xil_printf("RAWCOPY_SUBMIT_OK\r\n");

    for (;;) {
        busy_wait();
        xil_printf("RAWCOPY_SUBMIT_HEARTBEAT %u\r\n", heartbeat++);
    }
}
