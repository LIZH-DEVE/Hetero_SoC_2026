#include "xil_printf.h"
#include "xstatus.h"
#include "xparameters.h"
#include "xuartps.h"

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

    xil_printf("RAWCOPY UART DIAG\r\n");
    xil_printf("RAWCOPY_PLATFORM_OK\r\n");

    for (;;) {
        busy_wait();
        xil_printf("RAWCOPY_UART_HEARTBEAT %u\r\n", heartbeat++);
    }
}
