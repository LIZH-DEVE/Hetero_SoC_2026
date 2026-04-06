#include "xil_printf.h"
#include "xparameters.h"
#include "xuartps.h"

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

int main(void)
{
    int status;

    status = uart1_init_115200();
    if (status != XST_SUCCESS) {
        for (;;) {
        }
    }

    xil_printf("system_wrapper uart smoke\r\n");
    xil_printf("uart1 ok\r\n");

    for (;;) {
    }
}
