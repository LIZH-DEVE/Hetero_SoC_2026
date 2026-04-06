#include <stdint.h>

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

#define DRIVER_INIT_RING_COUNT 1u

static XUartPs g_uart;
static dma_ring_desc_t g_ring[DRIVER_INIT_RING_COUNT]
    __attribute__((aligned(DMA_ALIGNMENT_BYTES)));

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
    dma_ring_ctx_t ctx;
    int status;
    unsigned heartbeat = 0U;

    status = uart1_init_115200();
    if (status != XST_SUCCESS) {
        for (;;) {
        }
    }

    dma_ring_init(&ctx,
                  DMA_CSR_BASE,
                  g_ring,
                  (uint32_t)(uintptr_t)g_ring,
                  DRIVER_INIT_RING_COUNT);

    xil_printf("RAWCOPY DRIVER INIT DIAG\r\n");
    xil_printf("RAWCOPY_DRIVER_INIT_OK csr=0x%08lx ring=0x%08lx count=%u desc=%u ctx=%u\r\n",
               (unsigned long)ctx.csr_base,
               (unsigned long)ctx.ring_base_phys,
               (unsigned)ctx.ring_size,
               (unsigned)sizeof(dma_ring_desc_t),
               (unsigned)sizeof(dma_ring_ctx_t));

    for (;;) {
        busy_wait();
        xil_printf("RAWCOPY_DRIVER_HEARTBEAT %u\r\n", heartbeat++);
    }
}
