#include <stdint.h>

#include "xil_printf.h"
#include "xstatus.h"
#include "xparameters.h"
#include "xuartps.h"
#include "dma_hw_regs.h"
#include "dma_mvp_ps_driver_ref.h"

#define STATIC_RING_ENTRY_COUNT 1u
#define STATIC_RAW_COPY_BYTES (DMA_RAW_COPY_LEN_MULTIPLE * 2u)

typedef struct {
    dma_ring_desc_t ring[STATIC_RING_ENTRY_COUNT];
    uint8_t guard[DMA_CACHELINE_BYTES];
} dma_desc_region_t;

typedef struct {
    uint8_t bytes[STATIC_RAW_COPY_BYTES];
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

int main(void)
{
    int status;
    unsigned heartbeat = 0U;

    status = uart1_init_115200();
    if (status != XST_SUCCESS) {
        for (;;) {
        }
    }

    xil_printf("RAWCOPY STATIC REGIONS DIAG\r\n");
    xil_printf("RAWCOPY_STATIC_REGIONS_OK desc=%u src=%u dst=%u\r\n",
               (unsigned)sizeof(g_desc_region),
               (unsigned)sizeof(g_src_region),
               (unsigned)sizeof(g_dst_region));
    xil_printf("RAWCOPY_STATIC_ADDR desc=0x%08lx src=0x%08lx dst=0x%08lx\r\n",
               (unsigned long)(uintptr_t)&g_desc_region,
               (unsigned long)(uintptr_t)&g_src_region,
               (unsigned long)(uintptr_t)&g_dst_region);

    for (;;) {
        busy_wait();
        xil_printf("RAWCOPY_STATIC_HEARTBEAT %u\r\n", heartbeat++);
    }
}
