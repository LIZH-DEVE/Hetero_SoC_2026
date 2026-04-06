#include <stdint.h>
#include <string.h>

#include "xparameters.h"
#include "xstatus.h"
#include "xil_cache.h"
#include "xil_io.h"
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

#define RAW_COPY_BYTES (DMA_RAW_COPY_LEN_MULTIPLE * 2u)
#define POLL_TIMEOUT_ITERS 2000000u
#define RING_ENTRY_COUNT 2u

#if (RAW_COPY_BYTES % DMA_RAW_COPY_LEN_MULTIPLE) != 0
#error "RAW_COPY_BYTES must be a 32-byte multiple"
#endif

typedef struct {
    dma_ring_desc_t ring[RING_ENTRY_COUNT];
    uint8_t guard[DMA_CACHELINE_BYTES];
} dma_desc_region_t;

typedef struct {
    uint8_t bytes[RAW_COPY_BYTES];
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

static void print_csw(uint32_t csw)
{
    xil_printf("  CSW=0x%08x owner=%u done=%u err=%u sts=%u\r\n",
               (unsigned int)csw,
               (unsigned int)((csw & DMA_DESC_CSW_OWNER) != 0u),
               (unsigned int)((csw & DMA_DESC_CSW_DONE) != 0u),
               (unsigned int)((csw & DMA_DESC_CSW_ERR) != 0u),
               (unsigned int)(csw & DMA_DESC_CSW_MASK_STS));
}

static int compare_buffers(const uint8_t *lhs, const uint8_t *rhs, uint32_t len)
{
    uint32_t i;

    for (i = 0; i < len; ++i) {
        if (lhs[i] != rhs[i]) {
            xil_printf("  mismatch[%u]: got=0x%02x exp=0x%02x\r\n",
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

static void clear_regions(void)
{
    memset(&g_desc_region, 0, sizeof(g_desc_region));
    memset(&g_src_region, 0, sizeof(g_src_region));
    memset(&g_dst_region, 0, sizeof(g_dst_region));
}

static void seed_raw_copy_buffers(void)
{
    uint32_t i;

    for (i = 0; i < RAW_COPY_BYTES; ++i) {
        g_src_buffer[i] = (uint8_t)(0x40u + i);
        g_dst_buffer[i] = 0x00u;
    }
}

static void print_dma_snapshot(const dma_ring_ctx_t *ctx)
{
    xil_printf("DMA raw-copy smoke image\r\n");
    xil_printf("  contract_ver = %u\r\n", (unsigned int)DMA_CONTRACT_VERSION);
    xil_printf("  csr_base     = 0x%08x\r\n", (unsigned int)ctx->csr_base);
    xil_printf("  ring_base    = 0x%08x\r\n", (unsigned int)ctx->ring_base_phys);
    xil_printf("  ring_size    = %u\r\n", (unsigned int)ctx->ring_size);
    xil_printf("  src_addr     = 0x%08x\r\n", (unsigned int)(uintptr_t)g_src_buffer);
    xil_printf("  dst_addr     = 0x%08x\r\n", (unsigned int)(uintptr_t)g_dst_buffer);
    xil_printf("  len          = %u\r\n", (unsigned int)RAW_COPY_BYTES);
}

int main(void)
{
    dma_ring_ctx_t ctx;
    uint32_t csw = 0u;
    int rc;

    rc = uart1_init_115200();
    if (rc != XST_SUCCESS) {
        for (;;) {
        }
    }

    xil_printf("RAWCOPY_STAGE INIT\r\n");
    clear_regions();
    seed_raw_copy_buffers();

    dma_ring_init(&ctx,
                  DMA_CSR_BASE,
                  g_ring,
                  (uint32_t)(uintptr_t)g_ring,
                  RING_ENTRY_COUNT);

    xil_printf("RAWCOPY_STAGE RESET\r\n");
    dma_ring_soft_reset(&ctx);
    dma_ring_init(&ctx,
                  DMA_CSR_BASE,
                  g_ring,
                  (uint32_t)(uintptr_t)g_ring,
                  RING_ENTRY_COUNT);

    print_dma_snapshot(&ctx);

    xil_printf("RAWCOPY_STAGE SUBMIT\r\n");
    rc = dma_ring_submit_raw_copy(&ctx,
                                  (uint32_t)(uintptr_t)g_dst_buffer,
                                  (uint32_t)(uintptr_t)g_src_buffer,
                                  RAW_COPY_BYTES,
                                  g_src_buffer,
                                  RAW_COPY_BYTES);
    if (rc != 0) {
        xil_printf("raw-copy submit failed: %d\r\n", rc);
        xil_printf("DMA raw-copy smoke FAIL\r\n");
        return 1;
    }

    xil_printf("RAWCOPY_STAGE WAIT_CSW\r\n");
    rc = wait_for_csw(g_ring, &csw);
    print_csw(csw);
    if (rc != 0) {
        xil_printf("raw-copy poll failed: %d\r\n", rc);
        xil_printf("DMA raw-copy smoke FAIL\r\n");
        return 2;
    }

    xil_printf("RAWCOPY_STAGE INVALIDATE_DST\r\n");
    dma_ring_invalidate_result(g_dst_buffer, RAW_COPY_BYTES);

    xil_printf("RAWCOPY_STAGE COMPARE\r\n");
    if (compare_buffers(g_src_buffer, g_dst_buffer, RAW_COPY_BYTES) != 0) {
        xil_printf("raw-copy payload compare failed\r\n");
        xil_printf("DMA raw-copy smoke FAIL\r\n");
        return 3;
    }

    xil_printf("DMA raw-copy smoke PASS\r\n");
    return 0;
}
