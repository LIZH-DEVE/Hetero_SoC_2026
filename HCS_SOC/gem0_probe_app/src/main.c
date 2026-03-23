#include <stdint.h>
#include <string.h>

#include "sleep.h"
#include "xemacps.h"
#include "xemacps_bd.h"
#include "xemacps_bdring.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xparameters.h"
#include "xparameters_ps.h"

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
#define GEM0_CLK_CTRL_1G 0x00100141U
#define GEM0_CLK_CTRL_100 (((uint32_t)XPAR_XEMACPS_0_ENET_SLCR_100Mbps_DIV1 << 20) | \
                           ((uint32_t)XPAR_XEMACPS_0_ENET_SLCR_100Mbps_DIV0 << 8)  | 0x00000001U)
#define GEM0_CLK_CTRL_1000 (((uint32_t)XPAR_XEMACPS_0_ENET_SLCR_1000Mbps_DIV1 << 20) | \
                            ((uint32_t)XPAR_XEMACPS_0_ENET_SLCR_1000Mbps_DIV0 << 8)  | 0x00000001U)
#define GEM0_MIO_16_ADDR 0xF8000740U
#define GEM0_MIO_17_ADDR 0xF8000744U
#define GEM0_MIO_18_ADDR 0xF8000748U
#define GEM0_MIO_19_ADDR 0xF800074CU
#define GEM0_MIO_20_ADDR 0xF8000750U
#define GEM0_MIO_21_ADDR 0xF8000754U
#define GEM0_MIO_22_ADDR 0xF8000758U
#define GEM0_MIO_23_ADDR 0xF800075CU
#define GEM0_MIO_24_ADDR 0xF8000760U
#define GEM0_MIO_25_ADDR 0xF8000764U
#define GEM0_MIO_26_ADDR 0xF8000768U
#define GEM0_MIO_27_ADDR 0xF800076CU
#define GEM0_MIO_52_ADDR 0xF80007D0U
#define GEM0_MIO_53_ADDR 0xF80007D4U

#define UART1_CLOCK_CTRL_115200 0x00002003U
#define UART1_BRGR_115200 62U
#define UART1_BDIV_115200 6U

#define PROBE_FRAME_TYPE 0x88B5U
#define PROBE_TX_FRAME_LEN 60U
#define RX_WAIT_TIMEOUT_US 10000000U

#define RX_BD_COUNT 8U
#define TX_BD_COUNT 8U
#define RX_BUF_SIZE 1536U
#define TX_BUF_SIZE 1536U

#define PHY_REG_STATUS 1U
#define PHY_REG_ID1 2U
#define PHY_REG_ID2 3U
#define PHY_SCAN_LIMIT 32U
#define DEFAULT_PHY_ADDR 1U

#ifndef GEM0_FORCE_SPEED_MBPS
#define GEM0_FORCE_SPEED_MBPS 1000U
#endif

#if defined(XPAR_XEMACPS_0_PHY_MODE)
#define GEM0_PHY_MODE_STR XPAR_XEMACPS_0_PHY_MODE
#elif defined(XPAR_GEM0_PHY_MODE)
#define GEM0_PHY_MODE_STR XPAR_GEM0_PHY_MODE
#else
#define GEM0_PHY_MODE_STR "unspecified"
#endif

static XEmacPs g_emac;
static XEmacPs_Bd g_bd_template;
static uint8_t g_rx_bd_space[4096] __attribute__((aligned(64)));
static uint8_t g_tx_bd_space[4096] __attribute__((aligned(64)));
static uint8_t g_rx_frame[RX_BUF_SIZE] __attribute__((aligned(64)));
static uint8_t g_tx_frame[TX_BUF_SIZE] __attribute__((aligned(64)));
static const uint8_t g_local_mac[6] = {0x02, 0x0A, 0x35, 0x00, 0x01, 0x20};

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

    while (value != 0U && idx < (int)sizeof(digits)) {
        digits[idx++] = (char)('0' + (value % 10U));
        value /= 10U;
    }
    while (idx > 0) {
        uart_putchar(digits[--idx]);
    }
}

static void uart_putline_str(const char *label, const char *value) {
    uart_puts(label);
    uart_puts(value);
    uart_puts("\n");
}

static void uart_putline_hex32(const char *label, uint32_t value) {
    uart_puts(label);
    uart_puts("0x");
    uart_puthex32(value);
    uart_puts("\n");
}

static void uart_putline_hex16(const char *label, uint16_t value) {
    uart_puts(label);
    uart_puts("0x");
    uart_puthex16(value);
    uart_puts("\n");
}

static void uart_putline_hex8(const char *label, uint8_t value) {
    uart_puts(label);
    uart_puts("0x");
    uart_puthex8(value);
    uart_puts("\n");
}

static void print_bytes(const char *label, const uint8_t *data, uint32_t count) {
    uint32_t idx;

    uart_puts(label);
    uart_puts("\n");
    for (idx = 0; idx < count; ++idx) {
        if ((idx & 0x0FU) == 0U) {
            uart_puts("  ");
        }
        uart_puthex8(data[idx]);
        uart_puts(((idx & 0x0FU) == 0x0FU) ? "\n" : " ");
    }
    if ((count & 0x0FU) != 0U) {
        uart_puts("\n");
    }
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

static void dump_gem0_slcr_regs(void) {
    uart_putline_hex32("SLCR_APER_CLK_CTRL=", Xil_In32(APER_CLK_CTRL_ADDR));
    uart_putline_hex32("SLCR_GEM0_CLK_CTRL=", Xil_In32(GEM0_CLK_CTRL_ADDR));
    uart_putline_hex32("SLCR_MIO16=", Xil_In32(GEM0_MIO_16_ADDR));
    uart_putline_hex32("SLCR_MIO17=", Xil_In32(GEM0_MIO_17_ADDR));
    uart_putline_hex32("SLCR_MIO18=", Xil_In32(GEM0_MIO_18_ADDR));
    uart_putline_hex32("SLCR_MIO19=", Xil_In32(GEM0_MIO_19_ADDR));
    uart_putline_hex32("SLCR_MIO20=", Xil_In32(GEM0_MIO_20_ADDR));
    uart_putline_hex32("SLCR_MIO21=", Xil_In32(GEM0_MIO_21_ADDR));
    uart_putline_hex32("SLCR_MIO22=", Xil_In32(GEM0_MIO_22_ADDR));
    uart_putline_hex32("SLCR_MIO23=", Xil_In32(GEM0_MIO_23_ADDR));
    uart_putline_hex32("SLCR_MIO24=", Xil_In32(GEM0_MIO_24_ADDR));
    uart_putline_hex32("SLCR_MIO25=", Xil_In32(GEM0_MIO_25_ADDR));
    uart_putline_hex32("SLCR_MIO26=", Xil_In32(GEM0_MIO_26_ADDR));
    uart_putline_hex32("SLCR_MIO27=", Xil_In32(GEM0_MIO_27_ADDR));
    uart_putline_hex32("SLCR_MIO52=", Xil_In32(GEM0_MIO_52_ADDR));
    uart_putline_hex32("SLCR_MIO53=", Xil_In32(GEM0_MIO_53_ADDR));
}

static void dump_gem0_regs(XEmacPs *emac) {
    dump_gem0_slcr_regs();
    uart_putline_hex32("GEM0_NWCTRL=", XEmacPs_ReadReg(emac->Config.BaseAddress, XEMACPS_NWCTRL_OFFSET));
    uart_putline_hex32("GEM0_NWCFG=", XEmacPs_ReadReg(emac->Config.BaseAddress, XEMACPS_NWCFG_OFFSET));
    uart_putline_hex32("GEM0_NWSR=", XEmacPs_ReadReg(emac->Config.BaseAddress, XEMACPS_NWSR_OFFSET));
    uart_putline_hex32("GEM0_DMASR=", XEmacPs_ReadReg(emac->Config.BaseAddress, XEMACPS_TXSR_OFFSET));
    uart_putline_hex32("GEM0_RXSR=", XEmacPs_ReadReg(emac->Config.BaseAddress, XEMACPS_RXSR_OFFSET));
    uart_putline_hex32("GEM0_PHYMNTNC=", XEmacPs_ReadReg(emac->Config.BaseAddress, XEMACPS_PHYMNTNC_OFFSET));
}

static void dump_phy_scan(XEmacPs *emac) {
    uint32_t addr;
    uint16_t status;
    uint16_t id1;
    uint16_t id2;
    int read_ok;

    uart_puts("PHY_SCAN_BEGIN\n");
    for (addr = 0U; addr < PHY_SCAN_LIMIT; ++addr) {
        read_ok = 1;
        if (XEmacPs_PhyRead(emac, addr, PHY_REG_STATUS, &status) != XST_SUCCESS) {
            read_ok = 0;
        }
        if (XEmacPs_PhyRead(emac, addr, PHY_REG_ID1, &id1) != XST_SUCCESS) {
            read_ok = 0;
        }
        if (XEmacPs_PhyRead(emac, addr, PHY_REG_ID2, &id2) != XST_SUCCESS) {
            read_ok = 0;
        }

        uart_puts("PHY_ADDR=");
        uart_puthex8((uint8_t)addr);
        uart_puts(" OK=");
        uart_putchar(read_ok ? '1' : '0');
        uart_puts(" ST=0x");
        uart_puthex16(status);
        uart_puts(" ID1=0x");
        uart_puthex16(id1);
        uart_puts(" ID2=0x");
        uart_puthex16(id2);
        uart_puts("\n");
    }
    uart_puts("PHY_SCAN_END\n");
}

static const char *mdio_divisor_name(XEmacPs_MdcDiv Divisor) {
    switch (Divisor) {
    case MDC_DIV_8:
        return "8";
    case MDC_DIV_16:
        return "16";
    case MDC_DIV_32:
        return "32";
    case MDC_DIV_48:
        return "48";
    case MDC_DIV_64:
        return "64";
    case MDC_DIV_96:
        return "96";
    case MDC_DIV_128:
        return "128";
    case MDC_DIV_224:
        return "224";
    default:
        return "?";
    }
}

static int read_phy_triplet(XEmacPs *emac, uint32_t phy_addr,
                            uint16_t *status_out,
                            uint16_t *id1_out,
                            uint16_t *id2_out) {
    if (XEmacPs_PhyRead(emac, phy_addr, PHY_REG_STATUS, status_out) != XST_SUCCESS) {
        return -1;
    }
    if (XEmacPs_PhyRead(emac, phy_addr, PHY_REG_ID1, id1_out) != XST_SUCCESS) {
        return -1;
    }
    if (XEmacPs_PhyRead(emac, phy_addr, PHY_REG_ID2, id2_out) != XST_SUCCESS) {
        return -1;
    }
    return 0;
}

static int phy_triplet_looks_valid(uint16_t status, uint16_t id1, uint16_t id2) {
    return status != 0x0000U && status != 0xFFFFU &&
           id1 != 0x0000U && id1 != 0xFFFFU &&
           id2 != 0x0000U && id2 != 0xFFFFU;
}

static int probe_default_phy_with_divisor_sweep(XEmacPs *emac,
                                                uint16_t *status_out,
                                                uint16_t *id1_out,
                                                uint16_t *id2_out) {
    static const XEmacPs_MdcDiv divisors[] = {
        MDC_DIV_224, MDC_DIV_128, MDC_DIV_96, MDC_DIV_64,
        MDC_DIV_48, MDC_DIV_32, MDC_DIV_16, MDC_DIV_8
    };
    uint32_t idx;
    uint16_t status = 0U;
    uint16_t id1 = 0U;
    uint16_t id2 = 0U;
    int read_ok;

    uart_puts("PHY1_DIV_SWEEP_BEGIN\n");
    for (idx = 0U; idx < (sizeof(divisors) / sizeof(divisors[0])); ++idx) {
        XEmacPs_SetMdioDivisor(emac, divisors[idx]);
        usleep(1000U);
        read_ok = read_phy_triplet(emac, DEFAULT_PHY_ADDR, &status, &id1, &id2) == 0;

        uart_puts("PHY1_DIV=");
        uart_puts(mdio_divisor_name(divisors[idx]));
        uart_puts(" OK=");
        uart_putchar(read_ok ? '1' : '0');
        uart_puts(" ST=0x");
        uart_puthex16(status);
        uart_puts(" ID1=0x");
        uart_puthex16(id1);
        uart_puts(" ID2=0x");
        uart_puthex16(id2);
        uart_puts("\n");

        if (read_ok && phy_triplet_looks_valid(status, id1, id2)) {
            *status_out = status;
            *id1_out = id1;
            *id2_out = id2;
            uart_puts("PHY1_DIV_SWEEP_END\n");
            return 0;
        }
    }
    uart_puts("PHY1_DIV_SWEEP_END\n");
    return -1;
}

static int detect_phy_address(XEmacPs *emac, uint32_t *phy_addr_out, uint16_t *phy_id1_out, uint16_t *phy_id2_out) {
    uint32_t addr;
    uint16_t status = 0U;
    uint16_t id1 = 0U;
    uint16_t id2 = 0U;

    for (addr = 0U; addr < 32U; ++addr) {
        if (read_phy_triplet(emac, addr, &status, &id1, &id2) != 0) {
            continue;
        }
        if (phy_triplet_looks_valid(status, id1, id2)) {
            *phy_addr_out = addr;
            *phy_id1_out = id1;
            *phy_id2_out = id2;
            return 0;
        }
    }

    return -1;
}

static int setup_dma_rings(XEmacPs *emac) {
    int status;

    XEmacPs_BdClear(&g_bd_template);
    status = XEmacPs_BdRingCreate(
        &(XEmacPs_GetRxRing(emac)),
        (UINTPTR)g_rx_bd_space,
        (UINTPTR)g_rx_bd_space,
        XEMACPS_BD_ALIGNMENT,
        RX_BD_COUNT
    );
    if (status != XST_SUCCESS) {
        return status;
    }

    status = XEmacPs_BdRingClone(&(XEmacPs_GetRxRing(emac)), &g_bd_template, XEMACPS_RECV);
    if (status != XST_SUCCESS) {
        return status;
    }

    XEmacPs_BdClear(&g_bd_template);
    XEmacPs_BdSetStatus(&g_bd_template, XEMACPS_TXBUF_USED_MASK);

    status = XEmacPs_BdRingCreate(
        &(XEmacPs_GetTxRing(emac)),
        (UINTPTR)g_tx_bd_space,
        (UINTPTR)g_tx_bd_space,
        XEMACPS_BD_ALIGNMENT,
        TX_BD_COUNT
    );
    if (status != XST_SUCCESS) {
        return status;
    }

    status = XEmacPs_BdRingClone(&(XEmacPs_GetTxRing(emac)), &g_bd_template, XEMACPS_SEND);
    if (status != XST_SUCCESS) {
        return status;
    }

    XEmacPs_SetQueuePtr(emac, emac->RxBdRing.BaseBdAddr, 0, XEMACPS_RECV);
    XEmacPs_SetQueuePtr(emac, emac->TxBdRing.BaseBdAddr, 0, XEMACPS_SEND);
    return XST_SUCCESS;
}

static int prime_rx_buffer(XEmacPs *emac) {
    XEmacPs_Bd *rx_bd;
    int status;

    status = XEmacPs_BdRingAlloc(&(XEmacPs_GetRxRing(emac)), 1U, &rx_bd);
    if (status != XST_SUCCESS) {
        return status;
    }

    memset(g_rx_frame, 0, sizeof(g_rx_frame));
    XEmacPs_BdSetAddressRx(rx_bd, (UINTPTR)g_rx_frame);
    status = XEmacPs_BdRingToHw(&(XEmacPs_GetRxRing(emac)), 1U, rx_bd);
    return status;
}

static int send_probe_frame(XEmacPs *emac) {
    XEmacPs_Bd *tx_bd;
    uint32_t i;
    int status;

    memset(g_tx_frame, 0, sizeof(g_tx_frame));
    for (i = 0; i < 6U; ++i) {
        g_tx_frame[i] = 0xFFU;
        g_tx_frame[6U + i] = g_local_mac[i];
    }
    g_tx_frame[12] = (uint8_t)(PROBE_FRAME_TYPE >> 8);
    g_tx_frame[13] = (uint8_t)(PROBE_FRAME_TYPE & 0xFFU);
    memcpy(&g_tx_frame[14], "HCS GEM0 PROBE", 14U);

    status = XEmacPs_BdRingAlloc(&(XEmacPs_GetTxRing(emac)), 1U, &tx_bd);
    if (status != XST_SUCCESS) {
        return status;
    }

    XEmacPs_BdSetAddressTx(tx_bd, (UINTPTR)g_tx_frame);
    XEmacPs_BdSetLength(tx_bd, PROBE_TX_FRAME_LEN);
    XEmacPs_BdClearTxUsed(tx_bd);
    XEmacPs_BdSetLast(tx_bd);

    status = XEmacPs_BdRingToHw(&(XEmacPs_GetTxRing(emac)), 1U, tx_bd);
    if (status != XST_SUCCESS) {
        return status;
    }

    XEmacPs_Transmit(emac);

    for (i = 0; i < 10000U; ++i) {
        if (XEmacPs_BdRingFromHwTx(&(XEmacPs_GetTxRing(emac)), 1U, &tx_bd) != 0U) {
            XEmacPs_BdRingFree(&(XEmacPs_GetTxRing(emac)), 1U, tx_bd);
            return 0;
        }
        usleep(100U);
    }

    return -1;
}

static int wait_for_rx_frame(XEmacPs *emac, uint32_t *rx_len_out) {
    XEmacPs_Bd *rx_bd;
    uint32_t elapsed = 0U;
    uint32_t rx_bufs;

    while (elapsed < RX_WAIT_TIMEOUT_US) {
        rx_bufs = XEmacPs_BdRingFromHwRx(&(XEmacPs_GetRxRing(emac)), 1U, &rx_bd);
        if (rx_bufs != 0U) {
            *rx_len_out = XEmacPs_GetRxFrameSize(emac, rx_bd);
            XEmacPs_BdRingFree(&(XEmacPs_GetRxRing(emac)), rx_bufs, rx_bd);
            return 0;
        }
        usleep(1000U);
        elapsed += 1000U;
    }

    return -1;
}

static int setup_gem0(XEmacPs *emac) {
    XEmacPs_Config *cfg;
    uint32_t phy_addr;
    uint16_t phy_status;
    uint16_t phy_id1;
    uint16_t phy_id2;
    int status;

#ifdef SDT
    cfg = XEmacPs_LookupConfig(XPAR_XEMACPS_0_BASEADDR);
#else
    cfg = XEmacPs_LookupConfig(XPAR_XEMACPS_0_DEVICE_ID);
#endif
    if (cfg == 0) {
        return -1;
    }

    status = XEmacPs_CfgInitialize(emac, cfg, cfg->BaseAddress);
    if (status != XST_SUCCESS) {
        return status;
    }

    gem0_force_probe_clock();
    XEmacPs_SetMdioDivisor(emac, MDC_DIV_224);
    XEmacPs_SetOperatingSpeed(emac, GEM0_FORCE_SPEED_MBPS);

    if (probe_default_phy_with_divisor_sweep(emac, &phy_status, &phy_id1, &phy_id2) == 0) {
        uart_putline_hex32("PHY_ADDR=", DEFAULT_PHY_ADDR);
        uart_putline_hex16("PHY_ST=", phy_status);
        uart_putline_hex16("PHY_ID1=", phy_id1);
        uart_putline_hex16("PHY_ID2=", phy_id2);
    } else if (detect_phy_address(emac, &phy_addr, &phy_id1, &phy_id2) == 0) {
        uart_putline_hex32("PHY_ADDR=", phy_addr);
        uart_putline_hex16("PHY_ID1=", phy_id1);
        uart_putline_hex16("PHY_ID2=", phy_id2);
    } else {
        uart_puts("PHY_DETECT=FAIL\n");
        dump_gem0_regs(emac);
        dump_phy_scan(emac);
    }

    status = XEmacPs_SetOptions(
        emac,
        XEMACPS_PROMISC_OPTION |
        XEMACPS_BROADCAST_OPTION |
        XEMACPS_FCS_STRIP_OPTION |
        XEMACPS_FCS_INSERT_OPTION
    );
    if (status != XST_SUCCESS) {
        return status;
    }

    status = XEmacPs_SetMacAddress(emac, (void *)g_local_mac, 1U);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = setup_dma_rings(emac);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = prime_rx_buffer(emac);
    if (status != XST_SUCCESS) {
        return status;
    }

    XEmacPs_Start(emac);
    return 0;
}

int main(void) {
    uint32_t rx_len = 0U;
    int status;

    Xil_ICacheDisable();
    Xil_DCacheDisable();

    uart1_bootstrap_115200();
    if (!uart_fifo_can_write()) {
        return -1;
    }

    uart_puts("BOOT GEM0 PROBE APP\n");
    uart_putline_hex32("GEM0_BASE=", XPAR_XEMACPS_0_BASEADDR);
    uart_putline_str("PHY_MODE=", GEM0_PHY_MODE_STR);
    uart_puts("GEM0_SPEED_FORCED=");
    uart_putdec(GEM0_FORCE_SPEED_MBPS);
    uart_puts("\n");

    status = setup_gem0(&g_emac);
    uart_putline_hex32("GEM0_SETUP_STATUS=", (uint32_t)status);
    if (status != 0) {
        uart_puts("GEM0_SETUP_FAIL\n");
        return -1;
    }

    status = send_probe_frame(&g_emac);
    uart_putline_hex32("GEM0_TX_STATUS=", (uint32_t)status);
    if (status == 0) {
        uart_puts("GEM0_TX_PROBE_SENT\n");
    }

    status = wait_for_rx_frame(&g_emac, &rx_len);
    uart_putline_hex32("GEM0_RX_STATUS=", (uint32_t)status);
    if (status == 0) {
        uart_putline_hex32("GEM0_RX_LEN=", rx_len);
        if (rx_len > 32U) {
            rx_len = 32U;
        }
        print_bytes("GEM0_RX_HEAD", g_rx_frame, rx_len);
        uart_puts("GEM0_RX_PASS\n");
    } else {
        uart_puts("GEM0_RX_TIMEOUT\n");
    }

    XEmacPs_Stop(&g_emac);
    uart_puts("GEM0_PROBE_DONE\n");
    return 0;
}
