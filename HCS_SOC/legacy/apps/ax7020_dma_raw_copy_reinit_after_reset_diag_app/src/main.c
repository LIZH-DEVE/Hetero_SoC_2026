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

#define REINIT_RING_COUNT 1u

static XUartPs g_uart;
static dma_ring_desc_t g_ring[REINIT_RING_COUNT]
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
                  REINIT_RING_COUNT);

    dma_ring_soft_reset(&ctx);

    xil_printf("RAWCOPY REINIT AFTER RESET DIAG\r\n");
    xil_printf("RAWCOPY_REINIT_AFTER_RESET_STAGE BEFORE_REINIT\r\n");

    dma_ring_init(&ctx,
                  DMA_CSR_BASE,
                  g_ring,
                  (uint32_t)(uintptr_t)g_ring,
                  REINIT_RING_COUNT);

    xil_printf("RAWCOPY_REINIT_AFTER_RESET_STAGE AFTER_REINIT csr=0x%08x ring=0x%08x count=%d sw_tail=%d\r\n",
               (unsigned int)ctx.csr_base,
               (unsigned int)ctx.ring_base_phys,
               (int)ctx.ring_size,
               (int)ctx.sw_tail);
    xil_printf("RAWCOPY_REINIT_AFTER_RESET_OK\r\n");

    for (;;) {
        busy_wait();
        xil_printf("RAWCOPY_REINIT_HEARTBEAT %u\r\n", heartbeat++);
    }
}
