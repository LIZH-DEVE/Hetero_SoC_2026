#include <stdint.h>
#include <string.h>

#include "xil_printf.h"
#include "xstatus.h"
#include "xparameters.h"
#include "xuartps.h"
#include "dma_hw_regs.h"
#include "dma_mvp_ps_driver_ref.h"

#define MEMORY_PREP_RING_ENTRY_COUNT 1u
#define MEMORY_PREP_RAW_COPY_BYTES (DMA_RAW_COPY_LEN_MULTIPLE * 2u)

typedef struct {
    dma_ring_desc_t ring[MEMORY_PREP_RING_ENTRY_COUNT];
    uint8_t guard[DMA_CACHELINE_BYTES];
} dma_desc_region_t;

typedef struct {
    uint8_t bytes[MEMORY_PREP_RAW_COPY_BYTES];
    uint8_t guard[DMA_CACHELINE_BYTES];
} dma_buffer_region_t;

static dma_desc_region_t g_desc_region
    __attribute__((aligned(DMA_ALIGNMENT_BYTES), section(".dma_desc_region")));
static dma_buffer_region_t g_src_region
    __attribute__((aligned(DMA_ALIGNMENT_BYTES), section(".dma_src_region")));
static dma_buffer_region_t g_dst_region
    __attribute__((aligned(DMA_ALIGNMENT_BYTES), section(".dma_dst_region")));

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

    for (i = 0; i < MEMORY_PREP_RAW_COPY_BYTES; ++i) {
        g_src_region.bytes[i] = (uint8_t)(0x40u + i);
        g_dst_region.bytes[i] = 0x00u;
    }
}

int main(void)
{
    int status;
    unsigned heartbeat = 0U;

    status = uart1_init_115200();
    if (status != XST_SUCCESS) {
        for (;;) {
        }
    }

    clear_regions();
    seed_raw_copy_buffers();

    xil_printf("RAWCOPY MEMORY PREP DIAG\r\n");
    xil_printf("RAWCOPY_MEMORY_PREP_OK src0=0x%02lx srcLast=0x%02lx dst0=0x%02lx descCsw=0x%08lx\r\n",
               (unsigned long)g_src_region.bytes[0],
               (unsigned long)g_src_region.bytes[MEMORY_PREP_RAW_COPY_BYTES - 1u],
               (unsigned long)g_dst_region.bytes[0],
               (unsigned long)g_desc_region.ring[0].csw);

    for (;;) {
        busy_wait();
        xil_printf("RAWCOPY_MEMORY_HEARTBEAT %u\r\n", heartbeat++);
    }
}
