#include <stdint.h>

#include "sleep.h"
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
#define UART_SR_TXEMPTY 0x00000008U

#define SLCR_UNLOCK_ADDR 0xF8000008U
#define SLCR_LOCK_ADDR 0xF8000004U
#define SLCR_UNLOCK_KEY 0x0000DF0DU
#define SLCR_LOCK_KEY 0x0000767BU
#define APER_CLK_CTRL_ADDR 0xF800012CU
#define UART_CLK_CTRL_ADDR 0xF8000154U
#define MIO_PIN_48_ADDR 0xF80007C0U
#define MIO_PIN_49_ADDR 0xF80007C4U

#define UART1_BAUD_PREFERRED 115200U
#define UART1_BAUD_FALLBACK 230400U
#define UART1_CLOCK_CTRL_115200 0x00002003U
#define UART1_BRGR_115200 62U
#define UART1_BDIV_115200 6U

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

#if defined(XPAR_CRYPTO_ACCEL_AXI_0_BASEADDR)
#define CRYPTO_BASE_ADDR XPAR_CRYPTO_ACCEL_AXI_0_BASEADDR
#else
#define CRYPTO_BASE_ADDR 0x43C00000U
#endif
#define REG_STATUS 0x08U
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

#define STATUS_FINGERPRINT_MASK 0xFFF00000U
#define STATUS_FINGERPRINT_SHIFT 20U

#define NET_CFG_ENABLE 0x00000001U
#define NET_CFG_INJECT_SEL 0x00000002U
#define NET_CFG_ARP_ENABLE 0x00000004U

#define TXCAP_STATUS_COUNT_MASK 0x0000007FU
#define TXCAP_STATUS_NONEMPTY 0x00010000U
#define TXCAP_STATUS_DONE 0x00020000U
#define TXCAP_STATUS_OVERFLOW 0x00040000U
#define INJ_STATUS_OVERFLOW 0x00040000U

#define LOCAL_IP 0xC0A80114U
#define LOCAL_MAC_LO 0x35000120U
#define LOCAL_MAC_HI 0x0000020AU

#define ARP_REQ_WORDS 10U
#define ARP_REPLY_WORDS 11U
#define UDP_REQ_WORDS 19U

#define REG32(offset) Xil_In32(STAGE1_BASE_ADDR + (offset))
#define WRITE32(offset, value) Xil_Out32(STAGE1_BASE_ADDR + (offset), (value))

static const uint32_t kArpRequest[ARP_REQ_WORDS] = {
    0xDEADBEEFU,
    0xAAAA1234U,
    0x56789ABCU,
    0x08060000U,
    0x00010800U,
    0x06040001U,
    0x12340000U,
    0x56789ABCU,
    0xC0A80102U,
    0xC0A80114U
};

static const uint32_t kExpectedArpReply[ARP_REPLY_WORDS] = {
    0x12345678U,
    0x9ABC020AU,
    0x35000120U,
    0x08060000U,
    0x00010800U,
    0x06040002U,
    0x020A3500U,
    0x0120C0A8U,
    0x01141234U,
    0x56789ABCU,
    0xC0A80102U
};

static const uint32_t kUdpRequest[UDP_REQ_WORDS] = {
    0xDEADBEEFU,
    0xAAAA1122U,
    0x33445566U,
    0x08000000U,
    0x003C0005U,
    0x00000000U,
    0x00000000U,
    0x0000C0A8U,
    0x01020000U,
    0x00001234U,
    0x56780028U,
    0xA0A1A2A3U,
    0xB0B1B2B3U,
    0xC0C1C2C3U,
    0xD0D1D2D3U,
    0xE0E1E2E3U,
    0xF0F1F2F3U,
    0x11223344U,
    0x55667788U
};

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

static void print_words(const char *label, const uint32_t *words, uint32_t count) {
    uint32_t idx;

    uart_puts(label);
    uart_puts("\n");
    for (idx = 0; idx < count; ++idx) {
        uart_puts("  [");
        uart_putdec(idx);
        uart_puts("] 0x");
        uart_puthex32(words[idx]);
        uart_puts("\n");
    }
}

static uint16_t calc_ipv4_checksum(uint16_t ip_total_len, uint32_t src_ip, uint32_t dst_ip) {
    uint32_t acc = 0U;

    acc += 0x4500U;
    acc += ip_total_len;
    acc += 0x1234U;
    acc += 0x4000U;
    acc += 0x4011U;
    acc += (src_ip >> 16) & 0xFFFFU;
    acc += src_ip & 0xFFFFU;
    acc += (dst_ip >> 16) & 0xFFFFU;
    acc += dst_ip & 0xFFFFU;

    acc = (acc & 0xFFFFU) + (acc >> 16);
    acc = (acc & 0xFFFFU) + (acc >> 16);
    return (uint16_t)(~acc & 0xFFFFU);
}

static void configure_stage1_network(void) {
    WRITE32(REG_NET_LOCAL_IP, LOCAL_IP);
    WRITE32(REG_NET_LOCAL_MAC_LO, LOCAL_MAC_LO);
    WRITE32(REG_NET_LOCAL_MAC_HI, LOCAL_MAC_HI);
    WRITE32(REG_NET_CFG0, NET_CFG_ENABLE | NET_CFG_INJECT_SEL | NET_CFG_ARP_ENABLE);
    io_barrier();
}

static void clear_stage1_buffers(void) {
    WRITE32(REG_TXCAP_CTRL, 0x00000001U);
    WRITE32(REG_INJ_CTRL, 0x00000001U);
    io_barrier();
    usleep(1000U);
}

static void print_stage1_status(const char *tag) {
    uart_puts(tag);
    uart_puts(" INJ_CTRL=");
    uart_puthex32(REG32(REG_INJ_CTRL));
    uart_puts(" INJ_STATUS=");
    uart_puthex32(REG32(REG_INJ_STATUS));
    uart_puts(" TXCAP_STATUS=");
    uart_puthex32(REG32(REG_TXCAP_STATUS));
    uart_puts(" NETDBG=");
    uart_puthex32(REG32(REG_NETDBG_STATUS));
    uart_puts("\n");
}

static int verify_applied_control(void) {
    uint32_t applied_cfg0 = REG32(REG_NET_APPLIED_CFG0);
    uint32_t applied_ip = REG32(REG_NET_APPLIED_LOCAL_IP);
    uint32_t applied_mac_lo = REG32(REG_NET_APPLIED_LOCAL_MAC_LO);
    uint32_t applied_mac_hi = REG32(REG_NET_APPLIED_LOCAL_MAC_HI);
    uint32_t expected_cfg0 = NET_CFG_ENABLE | NET_CFG_INJECT_SEL | NET_CFG_ARP_ENABLE;

    uart_putline_hex32("NET_APPLIED_CFG0=", applied_cfg0);
    uart_putline_hex32("NET_APPLIED_LOCAL_IP=", applied_ip);
    uart_putline_hex32("NET_APPLIED_LOCAL_MAC_LO=", applied_mac_lo);
    uart_putline_hex32("NET_APPLIED_LOCAL_MAC_HI=", applied_mac_hi);

    if (applied_cfg0 != expected_cfg0 ||
        applied_ip != LOCAL_IP ||
        applied_mac_lo != LOCAL_MAC_LO ||
        applied_mac_hi != LOCAL_MAC_HI) {
        uart_puts("CONTROL_MISMATCH\n");
        return -1;
    }

    uart_puts("CONTROL_APPLIED_OK\n");
    return 0;
}

static int inject_packet(const uint32_t *words, uint16_t word_count) {
    uint16_t idx;
    uint32_t inj_status;

    WRITE32(REG_INJ_CTRL, ((uint32_t)word_count << 16));
    io_barrier();
    usleep(1000U);

    for (idx = 0; idx < word_count; ++idx) {
        WRITE32(REG_INJ_DATA, words[idx]);
    }
    io_barrier();

    inj_status = REG32(REG_INJ_STATUS);
    if ((inj_status & INJ_STATUS_OVERFLOW) != 0U) {
        uart_putline_hex32("INJ_STATUS_OVERFLOW=", inj_status);
        return -1;
    }
    return 0;
}

static int wait_for_txcap(uint16_t min_words, uint32_t timeout_us, uint32_t *status_out) {
    uint32_t status = 0U;
    uint32_t elapsed = 0U;

    while (elapsed < timeout_us) {
        status = REG32(REG_TXCAP_STATUS);
        if (((status & TXCAP_STATUS_COUNT_MASK) >= min_words) &&
            ((status & TXCAP_STATUS_NONEMPTY) != 0U)) {
            if (status_out != 0) {
                *status_out = status;
            }
            return 0;
        }
        usleep(100U);
        elapsed += 100U;
    }

    if (status_out != 0) {
        *status_out = status;
    }
    return -1;
}

static void read_txcap_words(uint32_t *words, uint16_t count) {
    uint16_t idx;
    for (idx = 0; idx < count; ++idx) {
        words[idx] = REG32(REG_TXCAP_DATA);
    }
}

static int compare_words(const uint32_t *got, const uint32_t *expected, uint16_t count) {
    uint16_t idx;
    for (idx = 0; idx < count; ++idx) {
        if (got[idx] != expected[idx]) {
            return (int)idx + 1;
        }
    }
    return 0;
}

static int validate_udp_reply_header(const uint32_t *words, uint16_t count) {
    uint16_t checksum = calc_ipv4_checksum(0x003CU, LOCAL_IP, 0xC0A80102U);

    if (count < 11U) {
        return -1;
    }
    if (words[0] != 0x11223344U) return 1;
    if (words[1] != 0x5566020AU) return 2;
    if (words[2] != 0x35000120U) return 3;
    if (words[3] != 0x08004500U) return 4;
    if (words[4] != 0x003C1234U) return 5;
    if (words[5] != 0x40004011U) return 6;
    if (words[6] != (((uint32_t)checksum << 16) | 0xC0A8U)) return 7;
    if (words[7] != 0x0114C0A8U) return 8;
    if (words[8] != 0x01021234U) return 9;
    if (words[9] != 0x12340028U) return 10;
    return 0;
}

static int run_arp_test(void) {
    uint32_t tx_status;
    uint32_t reply_words[ARP_REPLY_WORDS];
    int cmp_rc;

    uart_puts("TEST ARP INJECT START\n");
    clear_stage1_buffers();
    print_stage1_status("TEST ARP AFTER_CLEAR");
    if (inject_packet(kArpRequest, ARP_REQ_WORDS) != 0) {
        uart_puts("TEST ARP INJECT FAIL=inject_overflow\n");
        return -1;
    }
    print_stage1_status("TEST ARP AFTER_INJECT");
    if (wait_for_txcap(ARP_REPLY_WORDS, 500000U, &tx_status) != 0) {
        print_stage1_status("TEST ARP AFTER_TIMEOUT");
        uart_putline_hex32("TEST ARP TXCAP_STATUS_TIMEOUT=", tx_status);
        return -1;
    }
    read_txcap_words(reply_words, ARP_REPLY_WORDS);
    cmp_rc = compare_words(reply_words, kExpectedArpReply, ARP_REPLY_WORDS);
    uart_putline_hex32("TEST ARP TXCAP_STATUS=", tx_status);
    uart_putline_hex16("TEST ARP WORDS=", (uint16_t)(tx_status & TXCAP_STATUS_COUNT_MASK));
    if (cmp_rc != 0) {
        uart_puts("TEST ARP FAIL_AT_WORD=");
        uart_putdec((uint32_t)cmp_rc - 1U);
        uart_puts("\n");
        print_words("TEST ARP CAPTURED", reply_words, ARP_REPLY_WORDS);
        return -1;
    }
    uart_puts("TEST ARP PASS\n");
    return 0;
}

static int run_udp_test(void) {
    uint32_t tx_status;
    uint32_t count;
    uint32_t reply_words[32];
    int header_rc;

    uart_puts("TEST UDP INJECT START\n");
    clear_stage1_buffers();
    print_stage1_status("TEST UDP AFTER_CLEAR");
    if (inject_packet(kUdpRequest, UDP_REQ_WORDS) != 0) {
        uart_puts("TEST UDP INJECT FAIL=inject_overflow\n");
        return -1;
    }
    print_stage1_status("TEST UDP AFTER_INJECT");
    if (wait_for_txcap(11U, 800000U, &tx_status) != 0) {
        print_stage1_status("TEST UDP AFTER_TIMEOUT");
        uart_putline_hex32("TEST UDP TXCAP_STATUS_TIMEOUT=", tx_status);
        return -1;
    }

    count = tx_status & TXCAP_STATUS_COUNT_MASK;
    if (count > 32U) {
        count = 32U;
    }
    read_txcap_words(reply_words, (uint16_t)count);
    header_rc = validate_udp_reply_header(reply_words, (uint16_t)count);

    uart_putline_hex32("TEST UDP TXCAP_STATUS=", tx_status);
    uart_putline_hex16("TEST UDP WORDS=", (uint16_t)count);
    if (header_rc != 0) {
        uart_puts("TEST UDP HEADER_FAIL=");
        uart_putdec((uint32_t)header_rc);
        uart_puts("\n");
        print_words("TEST UDP CAPTURED", reply_words, (uint16_t)count);
        return -1;
    }

    uart_puts("TEST UDP PASS\n");
    print_words("TEST UDP HEADER WORDS", reply_words, 11U);
    return 0;
}

int main(void) {
    uint32_t uart_sr_pre;
    uint32_t status;
    uint32_t fingerprint;
    int arp_rc;
    int udp_rc;

    Xil_ICacheDisable();
    Xil_DCacheDisable();

    uart1_bootstrap_115200();
    uart_sr_pre = uart_read_status();
    if (!uart_fifo_can_write()) {
        return -1;
    }

    uart_puts("BOOT NETWORK INJECT APP\n");
    uart_puts("UART_BAUD=115200 ALT=230400\n");
    uart_putline_hex32("UART_SR_PRE=", uart_sr_pre);
    uart_putline_hex32("UART_SR=", uart_read_status());
    uart_puts("UART_TXEMPTY=");
    uart_putdec((uart_read_status() & UART_SR_TXEMPTY) ? 1U : 0U);
    uart_puts("\n");

    status = Xil_In32(CRYPTO_BASE_ADDR + REG_STATUS);
    fingerprint = (status & STATUS_FINGERPRINT_MASK) >> STATUS_FINGERPRINT_SHIFT;
    uart_putline_hex32("STATUS=", status);
    uart_putline_hex32("FINGERPRINT=", fingerprint);

#ifdef STAGE1_BASE_FALLBACK
    uart_puts("PLATFORM_MISMATCH: using fallback STAGE1 base.\n");
#endif
    uart_putline_hex32("STAGE1_BASE=", STAGE1_BASE_ADDR);

    configure_stage1_network();
    uart_putline_hex32("NET_CFG0=", REG32(REG_NET_CFG0));
    uart_putline_hex32("NET_LOCAL_IP=", REG32(REG_NET_LOCAL_IP));
    uart_putline_hex32("NET_LOCAL_MAC_LO=", REG32(REG_NET_LOCAL_MAC_LO));
    uart_putline_hex32("NET_LOCAL_MAC_HI=", REG32(REG_NET_LOCAL_MAC_HI));
    if (verify_applied_control() != 0) {
        while (1) {
        }
    }

    arp_rc = run_arp_test();
    udp_rc = run_udp_test();

    uart_puts("SUMMARY ARP=");
    uart_puts((arp_rc == 0) ? "PASS" : "FAIL");
    uart_puts(" UDP=");
    uart_puts((udp_rc == 0) ? "PASS" : "FAIL");
    uart_puts("\n");

    while (1) {
    }

    return 0;
}
