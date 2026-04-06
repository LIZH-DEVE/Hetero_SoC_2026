#include <stdint.h>
#include <string.h>

#include "sleep.h"
#include "xemacps.h"
#include "xemacps_bd.h"
#include "xemacps_bdring.h"
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
#define GEM0_FORCE_SPEED_MBPS 100U
#define GEM0_CLK_CTRL_1000 (((uint32_t)XPAR_XEMACPS_0_ENET_SLCR_1000Mbps_DIV1 << 20) | \
                            ((uint32_t)XPAR_XEMACPS_0_ENET_SLCR_1000Mbps_DIV0 << 8)  | 0x00000001U)
#define GEM0_CLK_CTRL_100  (((uint32_t)XPAR_XEMACPS_0_ENET_SLCR_100Mbps_DIV1 << 20) | \
                            ((uint32_t)XPAR_XEMACPS_0_ENET_SLCR_100Mbps_DIV0 << 8)  | 0x00000001U)

#define UART1_CLOCK_CTRL_115200 0x00002003U
#define UART1_BRGR_115200 62U
#define UART1_BDIV_115200 6U

#define DEFAULT_PHY_ADDR 1U
#define PHY_REG_STATUS 1U
#define PHY_REG_ID1 2U
#define PHY_REG_ID2 3U
#define PHY_REG_PAGE_SELECT 0x1FU
#define PHY_REG_EXT_PAGE_SELECT 0x1EU
#define RTL8211E_DELAY_PAGE 0x0007U
#define RTL8211E_DELAY_EXT_PAGE 0x00A4U
#define RTL8211E_DELAY_REG 0x001CU
#define RTL8211E_TX_DELAY_MASK 0x0002U
#define RTL8211E_RX_DELAY_MASK 0x0004U

#if defined(XPAR_SYSTEM_DMA_SUBSYSTEM_V2_WRA_0_0_BASEADDR)
#define STAGE1_BASE_ADDR XPAR_SYSTEM_DMA_SUBSYSTEM_V2_WRA_0_0_BASEADDR
#elif defined(XPAR_SYSTEM_DMA_SUBSYSTEM_V2_WRA_0_BASEADDR)
#define STAGE1_BASE_ADDR XPAR_SYSTEM_DMA_SUBSYSTEM_V2_WRA_0_BASEADDR
#elif defined(XPAR_DMA_SUBSYSTEM_V2_WRA_0_0_BASEADDR)
#define STAGE1_BASE_ADDR XPAR_DMA_SUBSYSTEM_V2_WRA_0_0_BASEADDR
#elif defined(XPAR_DMA_SUBSYSTEM_V2_WRA_0_BASEADDR)
#define STAGE1_BASE_ADDR XPAR_DMA_SUBSYSTEM_V2_WRA_0_BASEADDR
#elif defined(XPAR_DMA_SUBSYSTEM_0_BASEADDR)
#define STAGE1_BASE_ADDR XPAR_DMA_SUBSYSTEM_0_BASEADDR
#else
#define STAGE1_BASE_ADDR 0x40000000U
#define STAGE1_BASE_FALLBACK 1
#endif

#define REG_NET_CFG0 0x90U
#define REG_NET_LOCAL_IP 0x94U
#define REG_NET_LOCAL_MAC_LO 0x98U
#define REG_NET_LOCAL_MAC_HI 0x9CU
#define REG_INJ_CTRL 0xA0U
#define REG_INJ_DATA 0xA4U
#define REG_INJ_STATUS 0xA8U
#define REG_TXCAP_CTRL 0xACU
#define REG_TXCAP_STATUS 0xB0U
#define REG_TXCAP_DATA 0xB4U
#define REG_NETDBG_STATUS 0xB8U
#define REG_NET_APPLIED_CFG0 0xBCU
#define REG_NET_APPLIED_LOCAL_IP 0xC0U
#define REG_NET_APPLIED_LOCAL_MAC_LO 0xC4U
#define REG_NET_APPLIED_LOCAL_MAC_HI 0xC8U

#define NET_CFG_ENABLE 0x00000001U
#define NET_CFG_INJECT_SEL 0x00000002U
#define NET_CFG_ARP_ENABLE 0x00000004U

#define TXCAP_STATUS_COUNT_MASK 0x0000007FU
#define TXCAP_STATUS_NONEMPTY 0x00010000U
#define TXCAP_STATUS_DONE 0x00020000U
#define TXCAP_STATUS_OVERFLOW 0x00040000U
#define INJ_STATUS_OVERFLOW 0x00040000U

#define RX_BD_COUNT 8U
#define TX_BD_COUNT 8U
#define RX_BUF_SIZE 1600U
#define TX_BUF_SIZE 1600U
#define WORK_BUF_SIZE 1600U
#define STAGE1_TIMEOUT_US 1000000U
#define CACHELINE_BYTES 32U

#define LOCAL_IP_BE 0xC0A80114U
#define LOCAL_MAC_LO 0x35000120U
#define LOCAL_MAC_HI 0x0000020AU

#define REG32(offset) Xil_In32(STAGE1_BASE_ADDR + (offset))
#define WRITE32(offset, value) Xil_Out32(STAGE1_BASE_ADDR + (offset), (value))

static XEmacPs g_emac;
static XEmacPs_Bd g_bd_template;
static uint8_t g_rx_bd_space[4096] __attribute__((aligned(64)));
static uint8_t g_tx_bd_space[4096] __attribute__((aligned(64)));
static uint8_t g_rx_dma_frame[RX_BUF_SIZE] __attribute__((aligned(64)));
static uint8_t g_tx_dma_frame[TX_BUF_SIZE] __attribute__((aligned(64)));
static uint8_t g_bridge_rx_frame[WORK_BUF_SIZE] __attribute__((aligned(64)));
static uint8_t g_bridge_tx_frame[WORK_BUF_SIZE] __attribute__((aligned(64)));
static const uint8_t g_local_mac[6] = {0x02, 0x0A, 0x35, 0x00, 0x01, 0x20};

typedef struct {
    uint32_t rx_frames;
    uint32_t tx_frames;
    uint32_t bridge_frames;
    uint32_t ignored_frames;
    uint32_t stage1_errors;
    uint32_t gem_errors;
} BridgeStats;

static BridgeStats g_stats;

typedef enum {
    FRAME_CLASS_OTHER = 0,
    FRAME_CLASS_ARP_FOR_ME,
    FRAME_CLASS_ARP_OTHER,
    FRAME_CLASS_IPV4_UDP_FOR_ME,
    FRAME_CLASS_IPV4_OTHER,
    FRAME_CLASS_SHORT
} FrameClass;

static inline uint32_t uart_read_status(void) {
    return Xil_In32(UART1_BASEADDR + UART_SR_OFFSET);
}

static inline void io_barrier(void) {
    __asm__ volatile ("dsb sy" ::: "memory");
    __asm__ volatile ("isb" ::: "memory");
}

static inline int uart_fifo_can_write(void) {
    return (uart_read_status() & UART_SR_TXFULL) == 0U;
}

static void cache_invalidate_range(const void *addr, uint32_t len) {
    uintptr_t start = ((uintptr_t)addr) & ~((uintptr_t)CACHELINE_BYTES - 1U);
    uintptr_t end = ((uintptr_t)addr + (uintptr_t)len + CACHELINE_BYTES - 1U) & ~((uintptr_t)CACHELINE_BYTES - 1U);
    Xil_DCacheInvalidateRange((INTPTR)start, (u32)(end - start));
}

static void cache_flush_range(const void *addr, uint32_t len) {
    uintptr_t start = ((uintptr_t)addr) & ~((uintptr_t)CACHELINE_BYTES - 1U);
    uintptr_t end = ((uintptr_t)addr + (uintptr_t)len + CACHELINE_BYTES - 1U) & ~((uintptr_t)CACHELINE_BYTES - 1U);
    Xil_DCacheFlushRange((INTPTR)start, (u32)(end - start));
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

static void uart_putline_dec(const char *label, uint32_t value) {
    uart_puts(label);
    uart_putdec(value);
    uart_puts("\n");
}

static void uart_dump_bytes(const char *label, const uint8_t *data, uint32_t length) {
    uint32_t idx;

    uart_puts(label);
    uart_puts("\n");
    for (idx = 0U; idx < length; ++idx) {
        if ((idx % 16U) == 0U) {
            uart_puts("  ");
        }
        uart_puthex8(data[idx]);
        if (idx + 1U < length) {
            uart_putchar(' ');
        }
        if (((idx % 16U) == 15U) || (idx + 1U == length)) {
            uart_puts("\n");
        }
    }
}

static void dump_gem0_regs(XEmacPs *emac) {
    uart_putline_hex32("GEM0_NWCTRL=", XEmacPs_ReadReg(emac->Config.BaseAddress, XEMACPS_NWCTRL_OFFSET));
    uart_putline_hex32("GEM0_NWCFG=", XEmacPs_ReadReg(emac->Config.BaseAddress, XEMACPS_NWCFG_OFFSET));
    uart_putline_hex32("GEM0_NWSR=", XEmacPs_ReadReg(emac->Config.BaseAddress, XEMACPS_NWSR_OFFSET));
    uart_putline_hex32("GEM0_TXSR=", XEmacPs_ReadReg(emac->Config.BaseAddress, XEMACPS_TXSR_OFFSET));
    uart_putline_hex32("GEM0_RXSR=", XEmacPs_ReadReg(emac->Config.BaseAddress, XEMACPS_RXSR_OFFSET));
}

static void dump_gem0_tx_path(XEmacPs *emac, const char *label) {
    uart_puts(label);
    uart_puts("\n");
    uart_putline_hex32("GEM0_NWCTRL=", XEmacPs_ReadReg(emac->Config.BaseAddress, XEMACPS_NWCTRL_OFFSET));
    uart_putline_hex32("GEM0_TXSR=", XEmacPs_ReadReg(emac->Config.BaseAddress, XEMACPS_TXSR_OFFSET));
    uart_putline_hex32("GEM0_TXQBASE=", XEmacPs_ReadReg(emac->Config.BaseAddress, XEMACPS_TXQBASE_OFFSET));
}

static uint16_t frame_ethertype(const uint8_t *frame, uint32_t length) {
    if (length < 14U) {
        return 0U;
    }
    return (uint16_t)(((uint16_t)frame[12] << 8) | frame[13]);
}

static void gem0_force_probe_clock(void) {
    uint32_t clk_cfg;

    if (GEM0_FORCE_SPEED_MBPS == 1000U) {
        clk_cfg = GEM0_CLK_CTRL_1000;
    } else {
        clk_cfg = GEM0_CLK_CTRL_100;
    }

    Xil_Out32(SLCR_UNLOCK_ADDR, SLCR_UNLOCK_KEY);
    Xil_Out32(
        GEM0_CLK_CTRL_ADDR,
        (Xil_In32(GEM0_CLK_CTRL_ADDR) & ~GEM0_CLK_CTRL_MASK) |
        (clk_cfg & GEM0_CLK_CTRL_MASK)
    );
    Xil_Out32(SLCR_LOCK_ADDR, SLCR_LOCK_KEY);
}

static int phy_triplet_looks_valid(uint16_t status, uint16_t id1, uint16_t id2) {
    return status != 0x0000U && status != 0xFFFFU &&
           id1 != 0x0000U && id1 != 0xFFFFU &&
           id2 != 0x0000U && id2 != 0xFFFFU;
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

static int rtl8211e_configure_rgmii_delays(XEmacPs *emac, uint32_t phy_addr) {
    uint16_t old_page = 0U;
    uint16_t delay_cfg = 0U;
    int status;

    status = XEmacPs_PhyRead(emac, phy_addr, PHY_REG_PAGE_SELECT, &old_page);
    if (status != XST_SUCCESS) {
        return -1;
    }

    status = XEmacPs_PhyWrite(emac, phy_addr, PHY_REG_PAGE_SELECT, RTL8211E_DELAY_PAGE);
    if (status != XST_SUCCESS) {
        return -2;
    }

    status = XEmacPs_PhyWrite(emac, phy_addr, PHY_REG_EXT_PAGE_SELECT, RTL8211E_DELAY_EXT_PAGE);
    if (status != XST_SUCCESS) {
        XEmacPs_PhyWrite(emac, phy_addr, PHY_REG_PAGE_SELECT, old_page);
        return -3;
    }

    status = XEmacPs_PhyRead(emac, phy_addr, RTL8211E_DELAY_REG, &delay_cfg);
    if (status != XST_SUCCESS) {
        XEmacPs_PhyWrite(emac, phy_addr, PHY_REG_PAGE_SELECT, old_page);
        return -4;
    }

    uart_putline_hex16("RTL8211E_DELAY_BEFORE=", delay_cfg);
    delay_cfg &= (uint16_t)~(RTL8211E_TX_DELAY_MASK | RTL8211E_RX_DELAY_MASK);
    delay_cfg |= (uint16_t)(RTL8211E_TX_DELAY_MASK | RTL8211E_RX_DELAY_MASK);

    status = XEmacPs_PhyWrite(emac, phy_addr, RTL8211E_DELAY_REG, delay_cfg);
    if (status != XST_SUCCESS) {
        XEmacPs_PhyWrite(emac, phy_addr, PHY_REG_PAGE_SELECT, old_page);
        return -5;
    }

    status = XEmacPs_PhyRead(emac, phy_addr, RTL8211E_DELAY_REG, &delay_cfg);
    if (status != XST_SUCCESS) {
        XEmacPs_PhyWrite(emac, phy_addr, PHY_REG_PAGE_SELECT, old_page);
        return -6;
    }
    uart_putline_hex16("RTL8211E_DELAY_AFTER=", delay_cfg);

    status = XEmacPs_PhyWrite(emac, phy_addr, PHY_REG_PAGE_SELECT, old_page);
    if (status != XST_SUCCESS) {
        return -7;
    }

    return 0;
}

static int setup_dma_rings(XEmacPs *emac) {
    int status;
    uint8_t tx_queue;

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

    tx_queue = (emac->Version > 2U) ? 1U : 0U;
    XEmacPs_SetQueuePtr(emac, emac->RxBdRing.BaseBdAddr, 0U, XEMACPS_RECV);
    XEmacPs_SetQueuePtr(emac, emac->TxBdRing.BaseBdAddr, tx_queue, XEMACPS_SEND);
    return XST_SUCCESS;
}

static int prime_rx_buffer(XEmacPs *emac) {
    XEmacPs_Bd *rx_bd;
    int status;

    memset(g_rx_dma_frame, 0, sizeof(g_rx_dma_frame));
    cache_flush_range(g_rx_dma_frame, sizeof(g_rx_dma_frame));

    status = XEmacPs_BdRingAlloc(&(XEmacPs_GetRxRing(emac)), 1U, &rx_bd);
    if (status != XST_SUCCESS) {
        return status;
    }
    XEmacPs_BdSetAddressRx(rx_bd, (UINTPTR)g_rx_dma_frame);
    return XEmacPs_BdRingToHw(&(XEmacPs_GetRxRing(emac)), 1U, rx_bd);
}

static int gem0_init(XEmacPs *emac) {
    XEmacPs_Config *cfg;
    uint16_t phy_status = 0U;
    uint16_t phy_id1 = 0U;
    uint16_t phy_id2 = 0U;
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
    usleep(1000U);

    status = read_phy_triplet(emac, DEFAULT_PHY_ADDR, &phy_status, &phy_id1, &phy_id2);
    uart_putline_hex32("PHY_STATUS_RET=", (uint32_t)status);
    uart_putline_hex16("PHY_ST=", phy_status);
    uart_putline_hex16("PHY_ID1=", phy_id1);
    uart_putline_hex16("PHY_ID2=", phy_id2);
    if (status != 0 || !phy_triplet_looks_valid(phy_status, phy_id1, phy_id2)) {
        return -2;
    }

    status = rtl8211e_configure_rgmii_delays(emac, DEFAULT_PHY_ADDR);
    uart_putline_hex32("RTL8211E_DELAY_CFG_STATUS=", (uint32_t)status);
    if (status != 0) {
        return -3;
    }

    status = XEmacPs_SetOptions(
        emac,
        XEMACPS_PROMISC_OPTION |
        XEMACPS_BROADCAST_OPTION |
        XEMACPS_MULTICAST_OPTION |
        XEMACPS_FCS_STRIP_OPTION |
        XEMACPS_FCS_INSERT_OPTION |
        XEMACPS_TRANSMITTER_ENABLE_OPTION |
        XEMACPS_RECEIVER_ENABLE_OPTION
    );
    if (status != XST_SUCCESS) {
        return status;
    }

    status = XEmacPs_SetMacAddress(emac, (void *)g_local_mac, 1U);
    if (status != XST_SUCCESS) {
        return status;
    }

    uart_putline_hex32("GEM0_VERSION=", emac->Version);

    status = setup_dma_rings(emac);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = prime_rx_buffer(emac);
    if (status != XST_SUCCESS) {
        return status;
    }

    XEmacPs_Start(emac);
    dump_gem0_regs(emac);
    return XST_SUCCESS;
}

static void configure_stage1_network(void) {
    WRITE32(REG_NET_LOCAL_IP, LOCAL_IP_BE);
    WRITE32(REG_NET_LOCAL_MAC_LO, LOCAL_MAC_LO);
    WRITE32(REG_NET_LOCAL_MAC_HI, LOCAL_MAC_HI);
    WRITE32(REG_NET_CFG0, NET_CFG_ENABLE | NET_CFG_INJECT_SEL | NET_CFG_ARP_ENABLE);
    io_barrier();
}

static int verify_stage1_applied_control(void) {
    uint32_t expected_cfg0 = NET_CFG_ENABLE | NET_CFG_INJECT_SEL | NET_CFG_ARP_ENABLE;
    uint32_t applied_cfg0 = REG32(REG_NET_APPLIED_CFG0);
    uint32_t applied_ip = REG32(REG_NET_APPLIED_LOCAL_IP);
    uint32_t applied_mac_lo = REG32(REG_NET_APPLIED_LOCAL_MAC_LO);
    uint32_t applied_mac_hi = REG32(REG_NET_APPLIED_LOCAL_MAC_HI);

    uart_putline_hex32("NET_APPLIED_CFG0=", applied_cfg0);
    uart_putline_hex32("NET_APPLIED_LOCAL_IP=", applied_ip);
    uart_putline_hex32("NET_APPLIED_LOCAL_MAC_LO=", applied_mac_lo);
    uart_putline_hex32("NET_APPLIED_LOCAL_MAC_HI=", applied_mac_hi);

    return (applied_cfg0 == expected_cfg0 &&
            applied_ip == LOCAL_IP_BE &&
            applied_mac_lo == LOCAL_MAC_LO &&
            applied_mac_hi == LOCAL_MAC_HI) ? 0 : -1;
}

static void stage1_clear_buffers(void) {
    WRITE32(REG_TXCAP_CTRL, 0x00000001U);
    WRITE32(REG_INJ_CTRL, 0x00000001U);
    io_barrier();
    usleep(1000U);
}

static uint32_t pack_be32_from_bytes(const uint8_t *data, uint32_t length, uint32_t offset) {
    uint32_t word = 0U;
    uint32_t idx;

    for (idx = 0U; idx < 4U; ++idx) {
        word <<= 8;
        if ((offset + idx) < length) {
            word |= data[offset + idx];
        }
    }
    return word;
}

static void unpack_be32_to_bytes(uint32_t word, uint8_t *data, uint32_t length, uint32_t offset) {
    uint32_t idx;
    for (idx = 0U; idx < 4U; ++idx) {
        if ((offset + idx) < length) {
            data[offset + idx] = (uint8_t)((word >> (24U - (idx * 8U))) & 0xFFU);
        }
    }
}

static FrameClass classify_frame(const uint8_t *frame, uint32_t length) {
    uint16_t ethertype;

    if (length < 14U) {
        return FRAME_CLASS_SHORT;
    }

    ethertype = frame_ethertype(frame, length);
    if (ethertype == 0x0806U) {
        if (length < 42U) {
            return FRAME_CLASS_SHORT;
        }
        if (memcmp(frame, "\xFF\xFF\xFF\xFF\xFF\xFF", 6) != 0) {
            return FRAME_CLASS_ARP_OTHER;
        }
        if (!(frame[20] == 0x00U && frame[21] == 0x01U)) {
            return FRAME_CLASS_ARP_OTHER;
        }
        return memcmp(&frame[38], "\xC0\xA8\x01\x14", 4) == 0 ? FRAME_CLASS_ARP_FOR_ME : FRAME_CLASS_ARP_OTHER;
    }

    if (ethertype == 0x0800U) {
        if (length < 34U) {
            return FRAME_CLASS_SHORT;
        }
        if (memcmp(frame, g_local_mac, 6) != 0) {
            return FRAME_CLASS_IPV4_OTHER;
        }
        if (frame[23] != 17U) {
            return FRAME_CLASS_IPV4_OTHER;
        }
        return memcmp(&frame[30], "\xC0\xA8\x01\x14", 4) == 0 ? FRAME_CLASS_IPV4_UDP_FOR_ME : FRAME_CLASS_IPV4_OTHER;
    }

    return FRAME_CLASS_OTHER;
}

static int frame_targets_stage1(const uint8_t *frame, uint32_t length) {
    FrameClass frame_class = classify_frame(frame, length);
    return (frame_class == FRAME_CLASS_ARP_FOR_ME || frame_class == FRAME_CLASS_IPV4_UDP_FOR_ME) ? 1 : 0;
}

static int stage1_inject_frame(const uint8_t *frame, uint32_t length) {
    uint32_t word_count;
    uint32_t idx;
    uint32_t inj_status;

    word_count = (length + 3U) >> 2;
    stage1_clear_buffers();
    WRITE32(REG_INJ_CTRL, (word_count << 16));
    io_barrier();
    usleep(1000U);

    for (idx = 0U; idx < word_count; ++idx) {
        WRITE32(REG_INJ_DATA, pack_be32_from_bytes(frame, length, idx * 4U));
    }
    io_barrier();

    inj_status = REG32(REG_INJ_STATUS);
    if ((inj_status & INJ_STATUS_OVERFLOW) != 0U) {
        uart_putline_hex32("INJ_STATUS_OVERFLOW=", inj_status);
        return -1;
    }
    return 0;
}

static int stage1_wait_capture(uint32_t timeout_us, uint32_t *status_out) {
    uint32_t status = 0U;
    uint32_t elapsed = 0U;

    while (elapsed < timeout_us) {
        status = REG32(REG_TXCAP_STATUS);
        if ((status & TXCAP_STATUS_NONEMPTY) != 0U &&
            (status & TXCAP_STATUS_DONE) != 0U &&
            (status & TXCAP_STATUS_COUNT_MASK) != 0U) {
            *status_out = status;
            return 0;
        }
        usleep(100U);
        elapsed += 100U;
    }

    *status_out = status;
    return -1;
}

static int stage1_read_capture_frame(uint8_t *out_frame, uint32_t capacity, uint32_t *out_length) {
    uint32_t status = REG32(REG_TXCAP_STATUS);
    uint32_t count = status & TXCAP_STATUS_COUNT_MASK;
    uint32_t idx;

    if ((status & TXCAP_STATUS_OVERFLOW) != 0U) {
        return -1;
    }
    if (count == 0U) {
        return -2;
    }
    if ((count * 4U) > capacity) {
        return -3;
    }

    *out_length = count * 4U;
    for (idx = 0U; idx < count; ++idx) {
        unpack_be32_to_bytes(REG32(REG_TXCAP_DATA), out_frame, *out_length, idx * 4U);
    }
    return 0;
}

static int gem0_rx_poll_once(XEmacPs *emac, uint8_t *out_frame, uint32_t capacity, uint32_t *out_length) {
    XEmacPs_Bd *rx_bd;
    uint32_t rx_bufs;
    uint32_t frame_len;
    int status;

    rx_bufs = XEmacPs_BdRingFromHwRx(&(XEmacPs_GetRxRing(emac)), 1U, &rx_bd);
    if (rx_bufs == 0U) {
        return 1;
    }

    frame_len = XEmacPs_GetRxFrameSize(emac, rx_bd);
    if (frame_len > capacity) {
        frame_len = capacity;
    }

    cache_invalidate_range(g_rx_dma_frame, RX_BUF_SIZE);
    memcpy(out_frame, g_rx_dma_frame, frame_len);
    *out_length = frame_len;

    status = XEmacPs_BdRingFree(&(XEmacPs_GetRxRing(emac)), rx_bufs, rx_bd);
    if (status != XST_SUCCESS) {
        return -1;
    }

    status = prime_rx_buffer(emac);
    if (status != XST_SUCCESS) {
        return -2;
    }

    return 0;
}

static int gem0_tx_send_frame(XEmacPs *emac, const uint8_t *frame, uint32_t length) {
    XEmacPs_Bd *tx_bd;
    uint32_t poll;
    uint32_t txsr;
    int status;

    if (length > TX_BUF_SIZE) {
        return -1;
    }

    memcpy(g_tx_dma_frame, frame, length);
    cache_flush_range(g_tx_dma_frame, length);

    status = XEmacPs_BdRingAlloc(&(XEmacPs_GetTxRing(emac)), 1U, &tx_bd);
    if (status != XST_SUCCESS) {
        return status;
    }

    XEmacPs_BdSetAddressTx(tx_bd, (UINTPTR)g_tx_dma_frame);
    XEmacPs_BdSetLength(tx_bd, length);
    XEmacPs_BdClearTxUsed(tx_bd);
    XEmacPs_BdSetLast(tx_bd);

    status = XEmacPs_BdRingToHw(&(XEmacPs_GetTxRing(emac)), 1U, tx_bd);
    if (status != XST_SUCCESS) {
        return status;
    }

    XEmacPs_WriteReg(emac->Config.BaseAddress, XEMACPS_TXSR_OFFSET,
                     XEMACPS_TXSR_ERROR_MASK |
                     XEMACPS_TXSR_TXCOMPL_MASK |
                     XEMACPS_TXSR_TXGO_MASK |
                     XEMACPS_TXSR_USEDREAD_MASK);
    XEmacPs_Transmit(emac);
    for (poll = 0U; poll < 10000U; ++poll) {
        txsr = XEmacPs_ReadReg(emac->Config.BaseAddress, XEMACPS_TXSR_OFFSET);
        if (XEmacPs_BdRingFromHwTx(&(XEmacPs_GetTxRing(emac)), 1U, &tx_bd) != 0U) {
            XEmacPs_BdRingFree(&(XEmacPs_GetTxRing(emac)), 1U, tx_bd);
            if ((txsr & (XEMACPS_TXSR_TXCOMPL_MASK | XEMACPS_TXSR_USEDREAD_MASK)) != 0U) {
                return 0;
            }
            return -3;
        }
        usleep(100U);
    }
    return -2;
}

static uint32_t build_arp_tx_smoke_frame(uint8_t *frame, uint32_t capacity) {
    static const uint8_t broadcast_mac[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    static const uint8_t zero_mac[6] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
    static const uint8_t local_ip[4] = {0xC0, 0xA8, 0x01, 0x14};
    static const uint8_t host_ip[4] = {0xC0, 0xA8, 0x01, 0x0A};

    if (capacity < 42U) {
        return 0U;
    }

    memset(frame, 0, 42U);

    memcpy(&frame[0], broadcast_mac, 6U);
    memcpy(&frame[6], g_local_mac, 6U);
    frame[12] = 0x08U;
    frame[13] = 0x06U;

    frame[14] = 0x00U;
    frame[15] = 0x01U;
    frame[16] = 0x08U;
    frame[17] = 0x00U;
    frame[18] = 0x06U;
    frame[19] = 0x04U;
    frame[20] = 0x00U;
    frame[21] = 0x01U;

    memcpy(&frame[22], g_local_mac, 6U);
    memcpy(&frame[28], local_ip, 4U);
    memcpy(&frame[32], zero_mac, 6U);
    memcpy(&frame[38], host_ip, 4U);

    return 42U;
}

static void diag_print_stats(void) {
    uart_putline_dec("STAT_RX=", g_stats.rx_frames);
    uart_putline_dec("STAT_TX=", g_stats.tx_frames);
    uart_putline_dec("STAT_BRIDGE=", g_stats.bridge_frames);
    uart_putline_dec("STAT_IGNORE=", g_stats.ignored_frames);
    uart_putline_dec("STAT_STAGE1_ERR=", g_stats.stage1_errors);
    uart_putline_dec("STAT_GEM_ERR=", g_stats.gem_errors);
    uart_putline_hex32("NETDBG=", REG32(REG_NETDBG_STATUS));
}

int main(void) {
    uint32_t rx_len = 0U;
    uint32_t tx_len = 0U;
    uint32_t capture_status = 0U;
    uint32_t smoke_len = 0U;
    uint16_t ethertype = 0U;
    FrameClass frame_class = FRAME_CLASS_OTHER;
    int status;

    Xil_ICacheEnable();
    Xil_DCacheDisable();

    uart1_bootstrap_115200();
    if (!uart_fifo_can_write()) {
        return -1;
    }

    uart_puts("BOOT GEM0 STAGE1 BRIDGE APP\n");
    uart_putline_hex32("GEM0_BASE=", XPAR_XEMACPS_0_BASEADDR);
    uart_putline_hex32("STAGE1_BASE=", STAGE1_BASE_ADDR);
    uart_putline_dec("GEM0_SPEED_FORCE=", GEM0_FORCE_SPEED_MBPS);
    uart_puts("DCACHE=OFF\n");
#ifdef STAGE1_BASE_FALLBACK
    uart_puts("PLATFORM_MISMATCH: using fallback STAGE1 base.\n");
#endif

    configure_stage1_network();
    if (verify_stage1_applied_control() != 0) {
        uart_puts("STAGE1_CONTROL_FAIL\n");
        while (1) {
        }
    }
    uart_puts("CONTROL_APPLIED_OK\n");

    status = gem0_init(&g_emac);
    uart_putline_hex32("GEM0_INIT_STATUS=", (uint32_t)status);
    if (status != 0) {
        uart_puts("GEM0_INIT_FAIL\n");
        while (1) {
        }
    }

    uart_puts("GEM0_FCS_PAD=ON\n");
    uart_puts("BRIDGE_READY\n");

    smoke_len = build_arp_tx_smoke_frame(g_bridge_tx_frame, sizeof(g_bridge_tx_frame));
    if (smoke_len != 0U) {
        uart_putline_dec("TX_SMOKE_LEN=", smoke_len);
        uart_dump_bytes("TX_SMOKE_BYTES", g_bridge_tx_frame, smoke_len);
        dump_gem0_tx_path(&g_emac, "TX_SMOKE_BEFORE");
        status = gem0_tx_send_frame(&g_emac, g_bridge_tx_frame, smoke_len);
        dump_gem0_tx_path(&g_emac, "TX_SMOKE_AFTER");
        if (status == 0) {
            uart_puts("TX_SMOKE_OK\n");
        } else {
            uart_putline_hex32("TX_SMOKE_ERR=", (uint32_t)status);
        }
    }

    while (1) {
        status = gem0_rx_poll_once(&g_emac, g_bridge_rx_frame, sizeof(g_bridge_rx_frame), &rx_len);
        if (status == 1) {
            usleep(1000U);
            continue;
        }
        if (status != 0) {
            g_stats.gem_errors++;
            uart_putline_hex32("GEM0_RX_ERR=", (uint32_t)status);
            continue;
        }

        g_stats.rx_frames++;
        ethertype = frame_ethertype(g_bridge_rx_frame, rx_len);
        frame_class = classify_frame(g_bridge_rx_frame, rx_len);
        if (frame_class == FRAME_CLASS_ARP_FOR_ME || frame_class == FRAME_CLASS_ARP_OTHER) {
            uart_putline_dec("RX_LEN=", rx_len);
            uart_putline_hex16("RX_ETHERTYPE=", ethertype);
            uart_puts((frame_class == FRAME_CLASS_ARP_FOR_ME) ? "RX_ARP_FOR_ME\n" : "RX_ARP_OTHER\n");
        } else if (frame_class == FRAME_CLASS_IPV4_UDP_FOR_ME) {
            uart_putline_dec("RX_LEN=", rx_len);
            uart_putline_hex16("RX_ETHERTYPE=", ethertype);
            uart_puts("RX_IPV4_UDP_FOR_ME\n");
        }

        if (!frame_targets_stage1(g_bridge_rx_frame, rx_len)) {
            g_stats.ignored_frames++;
            continue;
        }

        uart_puts("BRIDGE_INJECT_START\n");
        status = stage1_inject_frame(g_bridge_rx_frame, rx_len);
        if (status != 0) {
            g_stats.stage1_errors++;
            uart_puts("BRIDGE_INJECT_FAIL\n");
            stage1_clear_buffers();
            continue;
        }

        status = stage1_wait_capture(STAGE1_TIMEOUT_US, &capture_status);
        if (status != 0) {
            g_stats.stage1_errors++;
            uart_putline_hex32("TXCAP_TIMEOUT_STATUS=", capture_status);
            stage1_clear_buffers();
            continue;
        }

        status = stage1_read_capture_frame(g_bridge_tx_frame, sizeof(g_bridge_tx_frame), &tx_len);
        if (status != 0) {
            g_stats.stage1_errors++;
            uart_putline_hex32("TXCAP_READ_FAIL=", (uint32_t)status);
            stage1_clear_buffers();
            continue;
        }

        status = gem0_tx_send_frame(&g_emac, g_bridge_tx_frame, tx_len);
        if (status != 0) {
            g_stats.gem_errors++;
            uart_putline_hex32("GEM0_TX_ERR=", (uint32_t)status);
            continue;
        }

        g_stats.bridge_frames++;
        g_stats.tx_frames++;
        uart_putline_dec("BRIDGE_RX_LEN=", rx_len);
        uart_putline_dec("BRIDGE_TX_LEN=", tx_len);
        diag_print_stats();
    }
}
