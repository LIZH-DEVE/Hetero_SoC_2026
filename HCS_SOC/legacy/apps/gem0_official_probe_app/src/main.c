#include <stdint.h>

#include "sleep.h"
#include "xemacps.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xparameters.h"

#define UART1_BASEADDR 0xE0001000U
#define UART_CR_OFFSET 0x00U
#define UART_MR_OFFSET 0x04U
#define UART_BAUDGEN_OFFSET 0x18U
#define UART_BAUDDIV_OFFSET 0x34U
#define UART_SR_OFFSET 0x2CU
#define UART_FIFO_OFFSET 0x30U

#define UART_CR_RXRST 0x00000001U
#define UART_CR_TXRST 0x00000002U
#define UART_CR_RX_EN 0x00000004U
#define UART_CR_TX_EN 0x00000010U
#define UART_SR_TXFULL 0x00000010U

#define SLCR_UNLOCK_ADDR 0xF8000008U
#define SLCR_LOCK_ADDR 0xF8000004U
#define SLCR_UNLOCK_KEY 0x0000DF0DU
#define SLCR_LOCK_KEY 0x0000767BU
#define APER_CLK_CTRL_ADDR 0xF800012CU
#define UART_CLK_CTRL_ADDR 0xF8000154U
#define MIO_PIN_48_ADDR 0xF80007C0U
#define MIO_PIN_49_ADDR 0xF80007C4U
#define GEM0_CLK_CTRL_ADDR 0xF8000140U
#define GEM0_CLK_CTRL_MASK 0x03F03F71U
#define GEM0_CLK_CTRL_100 (((uint32_t)XPAR_XEMACPS_0_ENET_SLCR_100Mbps_DIV1 << 20) | \
                           ((uint32_t)XPAR_XEMACPS_0_ENET_SLCR_100Mbps_DIV0 << 8)  | 0x00000001U)
#define GEM0_CLK_CTRL_1000 (((uint32_t)XPAR_XEMACPS_0_ENET_SLCR_1000Mbps_DIV1 << 20) | \
                            ((uint32_t)XPAR_XEMACPS_0_ENET_SLCR_1000Mbps_DIV0 << 8)  | 0x00000001U)

#define UART1_CLOCK_CTRL_115200 0x00002003U
#define UART1_BRGR_115200 62U
#define UART1_BDIV_115200 6U

#define DEFAULT_PHY_ADDR 1U
#define PHY_REG_STATUS 1U
#define PHY_REG_ID1 2U
#define PHY_REG_ID2 3U

#ifndef GEM0_FORCE_SPEED_MBPS
#define GEM0_FORCE_SPEED_MBPS 1000U
#endif

static inline uint32_t uart_read_status(void) {
    return Xil_In32(UART1_BASEADDR + UART_SR_OFFSET);
}

static inline int uart_fifo_can_write(void) {
    return (uart_read_status() & UART_SR_TXFULL) == 0U;
}

static void uart1_bootstrap_115200(void) {
    Xil_Out32(SLCR_UNLOCK_ADDR, SLCR_UNLOCK_KEY);
    Xil_Out32(APER_CLK_CTRL_ADDR, Xil_In32(APER_CLK_CTRL_ADDR) | 0x00300000U);
    Xil_Out32(UART_CLK_CTRL_ADDR, UART1_CLOCK_CTRL_115200);
    Xil_Out32(MIO_PIN_48_ADDR, 0x000016E0U);
    Xil_Out32(MIO_PIN_49_ADDR, 0x000016E1U);
    Xil_Out32(SLCR_LOCK_ADDR, SLCR_LOCK_KEY);

    Xil_Out32(UART1_BASEADDR + UART_CR_OFFSET, UART_CR_TXRST | UART_CR_RXRST);
    Xil_Out32(UART1_BASEADDR + UART_MR_OFFSET, 0x00000020U);
    Xil_Out32(UART1_BASEADDR + UART_BAUDGEN_OFFSET, UART1_BRGR_115200);
    Xil_Out32(UART1_BASEADDR + UART_BAUDDIV_OFFSET, UART1_BDIV_115200);
    Xil_Out32(UART1_BASEADDR + UART_CR_OFFSET, UART_CR_TX_EN | UART_CR_RX_EN);
}

static void uart_putchar(char c) {
    volatile int timeout = 100000;
    while ((uart_read_status() & UART_SR_TXFULL) && --timeout > 0) {
    }
    Xil_Out32(UART1_BASEADDR + UART_FIFO_OFFSET, (uint32_t)c);
}

static void uart_puts(const char *str) {
    while (*str != '\0') {
        if (*str == '\n') {
            uart_putchar('\r');
        }
        uart_putchar(*str++);
    }
}

static void uart_puthex8(uint8_t value) {
    static const char hex_chars[] = "0123456789ABCDEF";
    uart_putchar(hex_chars[(value >> 4) & 0x0FU]);
    uart_putchar(hex_chars[value & 0x0FU]);
}

static void uart_puthex16(uint16_t value) {
    uart_puthex8((uint8_t)((value >> 8) & 0xFFU));
    uart_puthex8((uint8_t)(value & 0xFFU));
}

static void uart_puthex32(uint32_t value) {
    uart_puthex8((uint8_t)((value >> 24) & 0xFFU));
    uart_puthex8((uint8_t)((value >> 16) & 0xFFU));
    uart_puthex8((uint8_t)((value >> 8) & 0xFFU));
    uart_puthex8((uint8_t)(value & 0xFFU));
}

static void uart_putdec(uint32_t value) {
    char digits[10];
    int idx = 0;

    if (value == 0U) {
        uart_putchar('0');
        return;
    }

    while (value > 0U && idx < (int)sizeof(digits)) {
        digits[idx++] = (char)('0' + (value % 10U));
        value /= 10U;
    }

    while (idx > 0) {
        uart_putchar(digits[--idx]);
    }
}

static void uart_putline_hex16(const char *label, uint16_t value) {
    uart_puts(label);
    uart_puts("0x");
    uart_puthex16(value);
    uart_puts("\n");
}

static void uart_putline_hex32(const char *label, uint32_t value) {
    uart_puts(label);
    uart_puts("0x");
    uart_puthex32(value);
    uart_puts("\n");
}

static void gem0_force_probe_clock(void) {
    uint32_t clock_value = (GEM0_FORCE_SPEED_MBPS == 100U) ? GEM0_CLK_CTRL_100 : GEM0_CLK_CTRL_1000;
    Xil_Out32(SLCR_UNLOCK_ADDR, SLCR_UNLOCK_KEY);
    Xil_Out32(
        GEM0_CLK_CTRL_ADDR,
        (Xil_In32(GEM0_CLK_CTRL_ADDR) & ~GEM0_CLK_CTRL_MASK) |
        (clock_value & GEM0_CLK_CTRL_MASK)
    );
    Xil_Out32(SLCR_LOCK_ADDR, SLCR_LOCK_KEY);
}

static int phy_triplet_looks_valid(uint16_t status, uint16_t id1, uint16_t id2) {
    return status != 0x0000U && status != 0xFFFFU &&
           id1 != 0x0000U && id1 != 0xFFFFU &&
           id2 != 0x0000U && id2 != 0xFFFFU;
}

int main(void) {
    XEmacPs emac;
    XEmacPs_Config *cfg;
    uint16_t status = 0U;
    uint16_t id1 = 0U;
    uint16_t id2 = 0U;
    int ret;

    Xil_ICacheDisable();
    Xil_DCacheDisable();

    uart1_bootstrap_115200();
    if (!uart_fifo_can_write()) {
        return -1;
    }

    uart_puts("BOOT GEM0 OFFICIAL PROBE APP\n");
    uart_putline_hex32("GEM0_BASE=", XPAR_XEMACPS_0_BASEADDR);
    uart_puts("GEM0_SPEED_FORCED=");
    uart_putdec(GEM0_FORCE_SPEED_MBPS);
    uart_puts("\n");

#ifdef SDT
    cfg = XEmacPs_LookupConfig(XPAR_XEMACPS_0_BASEADDR);
#else
    cfg = XEmacPs_LookupConfig(XPAR_XEMACPS_0_DEVICE_ID);
#endif
    if (cfg == 0) {
        uart_puts("LOOKUP_CONFIG_FAIL\n");
        return -1;
    }

    ret = XEmacPs_CfgInitialize(&emac, cfg, cfg->BaseAddress);
    uart_putline_hex32("CFGINIT=", (uint32_t)ret);
    if (ret != XST_SUCCESS) {
        uart_puts("CFGINIT_FAIL\n");
        return -1;
    }

    gem0_force_probe_clock();
    XEmacPs_SetMdioDivisor(&emac, MDC_DIV_224);
    XEmacPs_SetOperatingSpeed(&emac, GEM0_FORCE_SPEED_MBPS);
    usleep(1000U);

    ret = XEmacPs_PhyRead(&emac, DEFAULT_PHY_ADDR, PHY_REG_STATUS, &status);
    uart_putline_hex32("PHY_STATUS_RET=", (uint32_t)ret);
    uart_putline_hex16("PHY_ST=", status);
    ret = XEmacPs_PhyRead(&emac, DEFAULT_PHY_ADDR, PHY_REG_ID1, &id1);
    uart_putline_hex32("PHY_ID1_RET=", (uint32_t)ret);
    uart_putline_hex16("PHY_ID1=", id1);
    ret = XEmacPs_PhyRead(&emac, DEFAULT_PHY_ADDR, PHY_REG_ID2, &id2);
    uart_putline_hex32("PHY_ID2_RET=", (uint32_t)ret);
    uart_putline_hex16("PHY_ID2=", id2);

    uart_putline_hex32("GEM0_NWCTRL=", XEmacPs_ReadReg(emac.Config.BaseAddress, XEMACPS_NWCTRL_OFFSET));
    uart_putline_hex32("GEM0_NWCFG=", XEmacPs_ReadReg(emac.Config.BaseAddress, XEMACPS_NWCFG_OFFSET));
    uart_putline_hex32("GEM0_NWSR=", XEmacPs_ReadReg(emac.Config.BaseAddress, XEMACPS_NWSR_OFFSET));

    if (phy_triplet_looks_valid(status, id1, id2)) {
        uart_puts("OFFICIAL_PHY_PASS\n");
    } else {
        uart_puts("OFFICIAL_PHY_FAIL\n");
    }

    uart_puts("GEM0_OFFICIAL_PROBE_DONE\n");
    return 0;
}
