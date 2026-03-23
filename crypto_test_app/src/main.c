/*
 * Minimal UART1 Verification Program for Zynq-7020 (AX7020)
 *
 * Purpose: Verify that ps7_init.tcl correctly initializes UART1.
 * Expected: PuTTY shows 'Z' immediately, then 'A' every ~1 second.
 *
 * If this works, replace this file with your full crypto test suite.
 */
#include "xil_io.h"
#include "xil_cache.h"

/* UART1 registers */
#define UART1_BASE    0xE0001000
#define UART1_CR      0xE0001000  /* Control Register */
#define UART1_MR      0xE0001004  /* Mode Register */
#define UART1_SR      0xE000102C  /* Channel Status Register */
#define UART1_FIFO    0xE0001030  /* TX/RX FIFO */
#define UART1_BAUDGEN 0xE0001018  /* Baud Rate Generator */
#define UART1_BAUDDIV 0xE0001034  /* Baud Rate Divider */

/* Status register bits */
#define UART_SR_TXFULL  0x00000010  /* TX FIFO full */
#define UART_SR_TXEMPTY 0x00000008  /* TX FIFO empty */

/* APER_CLK_CTRL register for peripheral clock gating */
#define APER_CLK_CTRL 0xF800012C

static void uart1_putchar(char c) {
    /* Wait until TX FIFO is not full */
    while (Xil_In32(UART1_SR) & UART_SR_TXFULL);
    Xil_Out32(UART1_FIFO, (u32)c);
}

static void uart1_puts(const char *s) {
    while (*s) {
        if (*s == '\n') uart1_putchar('\r');
        uart1_putchar(*s++);
    }
}

static void uart1_puthex32(u32 val) {
    const char hex[] = "0123456789ABCDEF";
    for (int i = 28; i >= 0; i -= 4)
        uart1_putchar(hex[(val >> i) & 0xF]);
}

static void busy_delay(void) {
    /* ~1 second at 666MHz (rough) */
    for (volatile u32 i = 0; i < 66000000; i++);
}

int main(void)
{
    /* Disable caches to avoid any coherency issues during bringup */
    Xil_DCacheDisable();
    Xil_ICacheDisable();

    /*
     * Safety net: re-assert UART1 clock enable in APER_CLK_CTRL (bit 21)
     * and re-configure UART1 controller, in case ps7_init.tcl didn't run
     * or ran incompletely. This is belt-and-suspenders -- normally
     * ps7_init.tcl handles this.
     */
    u32 aper = Xil_In32(APER_CLK_CTRL);
    Xil_Out32(APER_CLK_CTRL, aper | (1 << 21));  /* UART1_CPU_1XCLKACT */

    /* Reset and configure UART1 controller */
    /* CR: TX_RST | RX_RST */
    Xil_Out32(UART1_CR, 0x03);
    /* Small delay for reset */
    for (volatile int i = 0; i < 1000; i++);

    /* BAUDDIV (CD register) = 6 */
    Xil_Out32(UART1_BAUDDIV, 0x06);
    /* BAUDGEN (BDIV register) = 124 (0x7C) */
    Xil_Out32(UART1_BAUDGEN, 0x7C);
    /* MR: 8-bit, no parity, 1 stop bit, normal mode */
    Xil_Out32(UART1_MR, 0x20);
    /* CR: TX_EN | RX_EN | STOPBRK */
    Xil_Out32(UART1_CR, 0x14);

    /* === Heartbeat marker 'Z' === */
    uart1_putchar('Z');

    /* Print diagnostic info */
    uart1_puts("\n\n===== UART1 ALIVE =====\n");
    uart1_puts("[DIAG] APER_CLK_CTRL = 0x");
    uart1_puthex32(Xil_In32(APER_CLK_CTRL));
    uart1_puts("\n");
    uart1_puts("[DIAG] UART1_CR  = 0x");
    uart1_puthex32(Xil_In32(UART1_CR));
    uart1_puts("\n");
    uart1_puts("[DIAG] UART1_MR  = 0x");
    uart1_puthex32(Xil_In32(UART1_MR));
    uart1_puts("\n");
    uart1_puts("[DIAG] UART1_SR  = 0x");
    uart1_puthex32(Xil_In32(UART1_SR));
    uart1_puts("\n");
    uart1_puts("[DIAG] BAUDGEN   = 0x");
    uart1_puthex32(Xil_In32(UART1_BAUDGEN));
    uart1_puts("\n");
    uart1_puts("[DIAG] BAUDDIV   = 0x");
    uart1_puthex32(Xil_In32(UART1_BAUDDIV));
    uart1_puts("\n");
    uart1_puts("[OK] If you see this, UART1 is working!\n");
    uart1_puts("===========================\n\n");

    /* Heartbeat loop: 'A' every ~1 second */
    while (1) {
        uart1_putchar('A');
        busy_delay();
    }

    return 0;
}
