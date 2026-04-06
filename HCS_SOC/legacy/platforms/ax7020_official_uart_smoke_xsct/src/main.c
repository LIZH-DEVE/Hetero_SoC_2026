#include "sleep.h"
#include "xil_printf.h"

int main(void)
{
    unsigned heartbeat = 0U;

    xil_printf("OFFICIAL XSCT UART SMOKE\r\n");
    xil_printf("APP_MAIN_ENTERED\r\n");

    for (;;) {
        sleep(1U);
        xil_printf("HEARTBEAT %u\r\n", heartbeat++);
    }
}
