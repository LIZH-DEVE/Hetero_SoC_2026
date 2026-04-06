#include <stdint.h>

#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xstatus.h"
#include "xuartps.h"

#define CRYPTO_BASE_ADDR 0x43C00000U
#define REG_CTRL 0x00U
#define REG_STATUS 0x08U
#define REG_KEY_0 0x10U

#define TEST_CASE_READ_ONLY 1U
#define TEST_CASE_WRITE_CTRL 2U
#define TEST_CASE_WRITE_KEY_1C 3U
#define TEST_CASE_WRITE_KEY_18 4U
#define TEST_CASE_WRITE_KEY_14 5U
#define TEST_CASE_WRITE_KEY_10 6U

#ifndef TEST_CASE_ID
#define TEST_CASE_ID TEST_CASE_READ_ONLY
#endif

#define HW_WRITE(offset, data) Xil_Out32(CRYPTO_BASE_ADDR + (offset), (data))
#define HW_READ(offset) Xil_In32(CRYPTO_BASE_ADDR + (offset))

static XUartPs g_uart;

static const char *test_case_name(void)
{
    switch (TEST_CASE_ID) {
    case TEST_CASE_READ_ONLY:
        return "read_only";
    case TEST_CASE_WRITE_CTRL:
        return "write_ctrl";
    case TEST_CASE_WRITE_KEY_1C:
        return "write_key_1c";
    case TEST_CASE_WRITE_KEY_18:
        return "write_key_18";
    case TEST_CASE_WRITE_KEY_14:
        return "write_key_14";
    case TEST_CASE_WRITE_KEY_10:
        return "write_key_10";
    default:
        return "unknown";
    }
}

static void print_status_line(const char *label, uint32_t value)
{
    xil_printf("%s0x%08lx\r\n", label, (unsigned long)value);
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

static void run_selected_test(void)
{
    switch (TEST_CASE_ID) {
    case TEST_CASE_READ_ONLY: {
        uint32_t status = HW_READ(REG_STATUS);
        xil_printf("TEST begin: read_only status\r\n");
        print_status_line("READ REG_STATUS = ", status);
        xil_printf("TEST done: read_only status\r\n");
        break;
    }

    case TEST_CASE_WRITE_CTRL:
        xil_printf("TEST begin: write_ctrl offset=0x00000000 value=0x00000002\r\n");
        HW_WRITE(REG_CTRL, 0x00000002U);
        xil_printf("TEST done: write_ctrl offset=0x00000000 value=0x00000002\r\n");
        break;

    case TEST_CASE_WRITE_KEY_1C:
        xil_printf("TEST begin: write_key_1c offset=0x0000001C value=0x2B7E1516\r\n");
        HW_WRITE(REG_KEY_0 + 0x0CU, 0x2B7E1516U);
        xil_printf("TEST done: write_key_1c offset=0x0000001C value=0x2B7E1516\r\n");
        break;

    case TEST_CASE_WRITE_KEY_18:
        xil_printf("TEST begin: write_key_18 offset=0x00000018 value=0x28AED2A6\r\n");
        HW_WRITE(REG_KEY_0 + 0x08U, 0x28AED2A6U);
        xil_printf("TEST done: write_key_18 offset=0x00000018 value=0x28AED2A6\r\n");
        break;

    case TEST_CASE_WRITE_KEY_14:
        xil_printf("TEST begin: write_key_14 offset=0x00000014 value=0xABF71588\r\n");
        HW_WRITE(REG_KEY_0 + 0x04U, 0xABF71588U);
        xil_printf("TEST done: write_key_14 offset=0x00000014 value=0xABF71588\r\n");
        break;

    case TEST_CASE_WRITE_KEY_10:
        xil_printf("TEST begin: write_key_10 offset=0x00000010 value=0x09CF4F3C\r\n");
        HW_WRITE(REG_KEY_0 + 0x00U, 0x09CF4F3CU);
        xil_printf("TEST done: write_key_10 offset=0x00000010 value=0x09CF4F3C\r\n");
        break;

    default:
        xil_printf("TEST begin: invalid_test_case\r\n");
        xil_printf("TEST done: invalid_test_case\r\n");
        break;
    }
}

int main(void)
{
    uint32_t initial_status;
    int status;

    Xil_ICacheDisable();
    Xil_DCacheDisable();

    status = uart1_init_115200();
    if (status != XST_SUCCESS) {
        for (;;) {
        }
    }

    xil_printf("AX7020 DIRECT CRYPTO WRITE SMOKE\r\n");
    xil_printf("TEST_CASE=%s\r\n", test_case_name());
    print_status_line("CRYPTO_BASE_ADDR = ", CRYPTO_BASE_ADDR);

    initial_status = HW_READ(REG_STATUS);
    print_status_line("REG_STATUS initial = ", initial_status);

    run_selected_test();

    for (;;) {
    }
}
