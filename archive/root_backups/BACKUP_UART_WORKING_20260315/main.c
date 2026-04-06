#include "xil_printf.h"
#include "xil_cache.h"
#include "sleep.h"
#include "xil_io.h"

#define UART1_BASEADDR 0xE0001000
#define UART_FIFO_OFFSET 0x30
#define UART_SR_OFFSET 0x2C
#define UART_SR_TXFULL 0x00000010

void uart_putchar(char c) {
    while (Xil_In32(UART1_BASEADDR + UART_SR_OFFSET) & UART_SR_TXFULL);
    Xil_Out32(UART1_BASEADDR + UART_FIFO_OFFSET, c);
}

void uart_puts(const char *str) {
    while (*str) {
        if (*str == '\n') uart_putchar('\r');
        uart_putchar(*str++);
    }
}

void uart_puthex32(uint32_t val) {
    const char hex_chars[] = "0123456789ABCDEF";
    for (int i = 28; i >= 0; i -= 4) {
        uart_putchar(hex_chars[(val >> i) & 0x0F]);
    }
}

int main() {
    for (volatile uint32_t i = 0; i < 10000; ++i) { }

    uart_puts("\n\n========================================\n");
    uart_puts("   UART ONLY Test - No Crypto Access\n");
    uart_puts("========================================\n\n");

    uart_puts("[TEST 1] Direct UART Output\n");
    uart_puts("  - This message is sent via direct UART register access\n");
    uart_puts("  - If you see this, UART is working!\n\n");

    uart_puts("[TEST 2] UART Status Register\n");
    uint32_t sr = Xil_In32(UART1_BASEADDR + UART_SR_OFFSET);
    uart_puts("  - UART_SR = 0x");
    uart_puthex32(sr);
    uart_puts("\n\n");

    uart_puts("[TEST 3] Loop Test\n");
    for (int i = 0; i < 10; i++) {
        uart_puts("  - Loop iteration ");
        uart_putchar('0' + i);
        uart_puts("\n");
    }

    uart_puts("\n[SUCCESS] UART Test Complete!\n");
    uart_puts("If you see this message, the UART hardware is working correctly.\n");
    uart_puts("The problem is with the crypto module access at 0x43C00000.\n");

    while(1) {
        uart_puts(".");
        for (volatile uint32_t i = 0; i < 50000000; ++i) { }
    }

    return 0;
}
