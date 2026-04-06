#include <stdint.h>
#include "xil_printf.h"
#include "xstatus.h"
#include "xparameters.h"
#include "xuartps.h"
#include "dma_hw_regs.h"
#include "dma_mvp_ps_driver_ref.h"

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
    const unsigned contract_version = DMA_CONTRACT_VERSION;
    const unsigned desc_size = (unsigned)sizeof(dma_ring_desc_t);
    const unsigned ctx_size = (unsigned)sizeof(dma_ring_ctx_t);

    status = uart1_init_115200();
    if (status != XST_SUCCESS) {
        for (;;) {
        }
    }

    xil_printf("RAWCOPY INCLUDES DIAG\r\n");
    xil_printf("RAWCOPY_INCLUDE_HEADERS_OK contract=%u desc=%u ctx=%u\r\n",
               contract_version,
               desc_size,
               ctx_size);
    xil_printf("RAWCOPY_INCLUDE_CSR ctrl=0x%08lx tail=0x%08lx doorbell=0x%08lx\r\n",
               (unsigned long)DMA_CSR_CTRL,
               (unsigned long)DMA_CSR_RING_SW_TAIL,
               (unsigned long)DMA_CSR_RING_DOORBELL);

    for (;;) {
        busy_wait();
        xil_printf("RAWCOPY_INCLUDE_HEARTBEAT %u\r\n", heartbeat++);
    }
}
