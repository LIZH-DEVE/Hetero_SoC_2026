#include <stdint.h>

#include "sleep.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"

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

#define CRYPTO_BASE_ADDR 0x43C00000U
#define REG_CTRL 0x00U
#define REG_STATUS 0x08U
#define REG_DATA_IN 0x04U
#define REG_DATA_OUT 0x0CU
#define REG_KEY_0 0x10U
#define REG_STALL_CNT 0x30U

#define ALGO_AES 0U
#define MODE_ENCRYPT 1U
#define MODE_DECRYPT 0U

#define STATUS_SYS_READY 0x00000001U
#define STATUS_TX_EMPTY 0x00000002U

#define HW_WRITE(offset, data) Xil_Out32(CRYPTO_BASE_ADDR + (offset), (data))
#define HW_READ(offset) Xil_In32(CRYPTO_BASE_ADDR + (offset))

#define SKIP_CRYPTO_TESTS 0

static inline void diag_mark(char c) {
    volatile int timeout = 50000;
    while ((Xil_In32(UART1_BASEADDR + UART_SR_OFFSET) & UART_SR_TXFULL) && --timeout > 0) {
    }
    Xil_Out32(UART1_BASEADDR + UART_FIFO_OFFSET, (uint32_t)c);
}

static uint32_t uart_read_status(void) {
    return Xil_In32(UART1_BASEADDR + UART_SR_OFFSET);
}

static int uart_fifo_can_write(void) {
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
    while ((Xil_In32(UART1_BASEADDR + UART_SR_OFFSET) & UART_SR_TXFULL) && --timeout > 0) {
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

static void uart_puthex32(uint32_t value) {
    uart_puthex8((uint8_t)((value >> 24) & 0xFFU));
    uart_puthex8((uint8_t)((value >> 16) & 0xFFU));
    uart_puthex8((uint8_t)((value >> 8) & 0xFFU));
    uart_puthex8((uint8_t)(value & 0xFFU));
}

static void print_hex_block_uart(const char *label, const uint8_t *data, int len) {
    int i;

    uart_puts(label);
    uart_puts(": \n    ");
    for (i = 0; i < len; ++i) {
        uart_puthex8(data[i]);
        uart_putchar(' ');
        if (((i + 1) % 16 == 0) && (i != len - 1)) {
            uart_puts("\n    ");
        }
    }
    uart_puts("\n");
}

static void load_key_128(const uint8_t *key) {
    int i;

    for (i = 0; i < 4; ++i) {
        uint32_t kv = ((uint32_t)key[i * 4] << 24) |
                      ((uint32_t)key[i * 4 + 1] << 16) |
                      ((uint32_t)key[i * 4 + 2] << 8) |
                      (uint32_t)key[i * 4 + 3];
        HW_WRITE(REG_KEY_0 + (uint32_t)((3 - i) * 4), kv);
    }
}

static int push_block(const uint8_t *in_block, uint8_t algo, uint8_t mode) {
    uint32_t status;
    int timeout;
    int i;
    uint32_t config = (uint32_t)(algo & 0x01U) | ((uint32_t)(mode & 0x01U) << 1);

    uart_puts("[DEBUG] Writing REG_CTRL...\n");
    HW_WRITE(REG_CTRL, config);
    uart_puts("[DEBUG] REG_CTRL done.\n");

    timeout = 100000;
    while (((status = HW_READ(REG_STATUS)) & STATUS_SYS_READY) == 0U) {
        --timeout;
        if (timeout <= 0) {
            uart_puts("[ERR] Engine is BUSY (sys_ready=0)! Cannot push new block.\n");
            return -1;
        }
    }

    uart_puts("[DEBUG] Pushing Data...");
    for (i = 0; i < 4; ++i) {
        uint32_t din = ((uint32_t)in_block[i * 4] << 24) |
                       ((uint32_t)in_block[i * 4 + 1] << 16) |
                       ((uint32_t)in_block[i * 4 + 2] << 8) |
                       (uint32_t)in_block[i * 4 + 3];
        HW_WRITE(REG_DATA_IN, din);
        uart_puts(">");
    }
    uart_puts(" done.\n");
    return 0;
}

static void push_block_raw(const uint8_t *in_block) {
    int i;

    for (i = 0; i < 4; ++i) {
        uint32_t din = ((uint32_t)in_block[i * 4] << 24) |
                       ((uint32_t)in_block[i * 4 + 1] << 16) |
                       ((uint32_t)in_block[i * 4 + 2] << 8) |
                       (uint32_t)in_block[i * 4 + 3];
        HW_WRITE(REG_DATA_IN, din);
    }
}

static int pull_block(uint8_t *out_block) {
    int timeout;
    int i;

    uart_puts("[DEBUG] Waiting for SYS_READY...");
    timeout = 100000;
    while ((HW_READ(REG_STATUS) & STATUS_SYS_READY) == 0U) {
        --timeout;
        if (timeout <= 0) {
            uart_puts("[ERR] Encryption Timeout!\n");
            return -1;
        }
    }
    uart_puts(" Ready.\n");

    uart_puts("[DEBUG] Pulling Data...");
    for (i = 0; i < 4; ++i) {
        timeout = 10000;
        while ((HW_READ(REG_STATUS) & STATUS_TX_EMPTY) != 0U) {
            --timeout;
            if (timeout <= 0) {
                uart_puts("[ERR] TX FIFO starved! Expected data but timed out.\n");
                return -1;
            }
        }

        uint32_t dout = HW_READ(REG_DATA_OUT);
        out_block[i * 4] = (uint8_t)((dout >> 24) & 0xFFU);
        out_block[i * 4 + 1] = (uint8_t)((dout >> 16) & 0xFFU);
        out_block[i * 4 + 2] = (uint8_t)((dout >> 8) & 0xFFU);
        out_block[i * 4 + 3] = (uint8_t)(dout & 0xFFU);
        uart_puts("<");
    }
    uart_puts(" done.\n");
    return 0;
}

static int process_block(const uint8_t *in_block, uint8_t *out_block, uint8_t algo, uint8_t mode) {
    if (push_block(in_block, algo, mode) < 0) {
        return -1;
    }
    return pull_block(out_block);
}

static const uint8_t sm4_key[16] = {
    0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF,
    0xFE, 0xDC, 0xBA, 0x98, 0x76, 0x54, 0x32, 0x10
};

static const uint8_t sm4_pt[16] = {
    0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF,
    0xFE, 0xDC, 0xBA, 0x98, 0x76, 0x54, 0x32, 0x10
};

static const uint8_t sm4_ct[16] = {
    0x68, 0x1E, 0xDF, 0x34, 0xD2, 0x06, 0x96, 0x5E,
    0x86, 0xB3, 0xE9, 0x4F, 0x53, 0x6E, 0x42, 0x46
};

static int compare_blocks(const uint8_t *a, const uint8_t *b, int len) {
    int i;

    for (i = 0; i < len; ++i) {
        if (a[i] != b[i]) {
            return 0;
        }
    }
    return 1;
}

static void test_aes_encrypt(void) {
    uint8_t output[16];
    const uint8_t aes_key[16] = {
        0x2B, 0x7E, 0x15, 0x16, 0x28, 0xAE, 0xD2, 0xA6,
        0xAB, 0xF7, 0x15, 0x88, 0x09, 0xCF, 0x4F, 0x3C
    };
    const uint8_t aes_pt[16] = {
        0x32, 0x43, 0xF6, 0xA8, 0x88, 0x5A, 0x30, 0x8D,
        0x31, 0x31, 0x98, 0xA2, 0xE0, 0x37, 0x07, 0x34
    };
    const uint8_t aes_expected_ct[16] = {
        0x39, 0x25, 0x84, 0x1D, 0x02, 0xDC, 0x09, 0xFB,
        0xDC, 0x11, 0x85, 0x97, 0x19, 0x6A, 0x0B, 0x32
    };

    uart_puts("\n--- [TEST] AES-128 Encryption ---\n");
    load_key_128(aes_key);
    process_block(aes_pt, output, ALGO_AES, MODE_ENCRYPT);
    print_hex_block_uart("[OUT] Ciphertext", output, 16);
    if (compare_blocks(output, aes_expected_ct, 16) != 0) {
        uart_puts("[PASS] AES Encryption Correct!\n");
    } else {
        uart_puts("[FAIL] AES Encryption Mismatch!\n");
    }
}

static void test_aes_decrypt(void) {
    uint8_t output[16];
    const uint8_t aes_key[16] = {
        0x2B, 0x7E, 0x15, 0x16, 0x28, 0xAE, 0xD2, 0xA6,
        0xAB, 0xF7, 0x15, 0x88, 0x09, 0xCF, 0x4F, 0x3C
    };
    const uint8_t aes_ct[16] = {
        0x39, 0x25, 0x84, 0x1D, 0x02, 0xDC, 0x09, 0xFB,
        0xDC, 0x11, 0x85, 0x97, 0x19, 0x6A, 0x0B, 0x32
    };
    const uint8_t aes_expected_pt[16] = {
        0x32, 0x43, 0xF6, 0xA8, 0x88, 0x5A, 0x30, 0x8D,
        0x31, 0x31, 0x98, 0xA2, 0xE0, 0x37, 0x07, 0x34
    };

    uart_puts("\n--- [TEST] AES-128 Decryption ---\n");
    load_key_128(aes_key);
    process_block(aes_ct, output, ALGO_AES, MODE_DECRYPT);
    print_hex_block_uart("[OUT] Plaintext", output, 16);
    if (compare_blocks(output, aes_expected_pt, 16) != 0) {
        uart_puts("[PASS] AES Decryption Correct!\n");
    } else {
        uart_puts("[FAIL] AES Decryption Mismatch!\n");
    }
}

static void test_sm4_all(void) {
    uint8_t output[16];

    uart_puts("\n--- [TEST] SM4-128 Encryption ---\n");
    load_key_128(sm4_key);
    process_block(sm4_pt, output, 1U, MODE_ENCRYPT);
    print_hex_block_uart("[OUT] SM4 Cipher", output, 16);
    if (compare_blocks(output, sm4_ct, 16) != 0) {
        uart_puts("[PASS] SM4 Encryption Correct!\n");
    } else {
        uart_puts("[FAIL] SM4 Encryption Mismatch!\n");
    }

    uart_puts("\n--- [TEST] SM4-128 Decryption ---\n");
    process_block(sm4_ct, output, 1U, MODE_DECRYPT);
    print_hex_block_uart("[OUT] SM4 Plain", output, 16);
    if (compare_blocks(output, sm4_pt, 16) != 0) {
        uart_puts("[PASS] SM4 Decryption Correct!\n");
    } else {
        uart_puts("[FAIL] SM4 Decryption Mismatch!\n");
    }
}

static void test_security_robustness(void) {
    uint8_t dummy_in[16] = {0};
    uint8_t dummy_out[16];
    const uint8_t test_key[16] = {
        0x2B, 0x7E, 0x15, 0x16, 0x28, 0xAE, 0xD2, 0xA6,
        0xAB, 0xF7, 0x15, 0x88, 0x09, 0xCF, 0x4F, 0x3C
    };
    uint32_t stall_start;
    uint32_t stall_end;
    uint32_t status;
    int i;
    int fail_count = 0;

    uart_puts("\n--- [SECURITY] Hardware WREADY Back-pressure Test (20 Blocks) ---\n");
    uart_puts("[SYS] Pushing 20 blocks FAST (skipping SYS_READY polling) to force AXI back-pressure...\n");

    HW_WRITE(REG_CTRL, (ALGO_AES & 0x01U) | ((uint32_t)MODE_ENCRYPT << 1));
    load_key_128(test_key);

    stall_start = HW_READ(REG_STALL_CNT);
    for (i = 0; i < 20; ++i) {
        dummy_in[0] = (uint8_t)i;
        push_block_raw(dummy_in);
        if ((i % 5) == 0) {
            uart_puts(">");
        }
    }
    stall_end = HW_READ(REG_STALL_CNT);

    uart_puts("\n[SYS] Burst Write Finish.\n");
    uart_puts("[SYS] Hardware Stall Cycles detected on AXI: ");
    uart_puthex32(stall_end - stall_start);
    uart_puts(" cycles.\n");

    status = HW_READ(REG_STATUS);
    uart_puts("[SYS] STATUS at full load: 0x");
    uart_puthex32(status);
    uart_puts("\n");

    uart_puts("[SYS] Draining results to verify data integrity...\n");
    for (i = 0; i < 20; ++i) {
        if (pull_block(dummy_out) != 0) {
            ++fail_count;
        }
        if ((i % 5) == 0) {
            uart_puts("<");
        }
    }

    if (fail_count == 0) {
        uart_puts("\n[PASS] Hardware WREADY Back-pressure verified! No data lost under burst load.\n");
    } else {
        uart_puts("\n[FAIL] Back-pressure leaked! Some blocks missed.\n");
    }

    uart_puts("\n--- [SECURITY] Exception Test: Short Packet (1 Word) ---\n");
    uart_puts("[SYS] Sending only 4 bytes (1 word) to 128-bit engine...\n");
    HW_WRITE(REG_DATA_IN, 0xDEADBEEFU);
    status = HW_READ(REG_STATUS);
    uart_puts("[SYS] STATUS: 0x");
    uart_puthex32(status);
    uart_puts("\n");
    if ((status & STATUS_SYS_READY) == 0U) {
        uart_puts("[OK] System is correctly BUSY (waiting for remaining 3 words).\n");
    }
    uart_puts("[SYS] Please use 'rst -system' in XSDB now to reset for next run.\n");
}

int main(void) {
    uint32_t uart_sr_before;
    uint32_t uart_sr_after;
    uint32_t status;
    uint16_t fingerprint;
    uint8_t rd_ptr;
    uint8_t wr_ptr;
    uint8_t f_empty;
    uint8_t f_full;

    uart_sr_before = uart_read_status();
    uart1_bootstrap_115200();
    for (volatile uint32_t i = 0; i < 1000U; ++i) {
    }
    uart_sr_after = uart_read_status();

    if (uart_fifo_can_write() != 0) {
        uart_puts("BOOT UART1 OK\n");
        uart_puts("UART_BAUD=115200 ALT=230400\n");
        uart_puts("UART_SR_PRE=0x");
        uart_puthex32(uart_sr_before);
        uart_puts("\n");
        uart_puts("UART_SR=0x");
        uart_puthex32(uart_sr_after);
        uart_puts("\n");
        uart_puts("UART_TXEMPTY=");
        uart_putchar((uart_sr_after & UART_SR_TXEMPTY) != 0U ? '1' : '0');
        uart_puts("\n");
    }

    diag_mark('1');
    uart_putchar('A');
    uart_putchar('B');
    uart_putchar('C');
    uart_putchar('\n');

    diag_mark('2');
    uart_puts("\n\n=======================================================\n");
    uart_puts("   HCS_SOC Bare-Metal Crypto Full Test Suite (v2.1-DIAG)   \n");
    uart_puts("=======================================================\n");

    diag_mark('3');
    uart_puts("[DIAG] About to read STATUS register at 0x43C00008...\n");
    status = HW_READ(REG_STATUS);
    diag_mark('4');

    uart_puts("[SYS] Initial STATUS: 0x");
    uart_puthex32(status);
    uart_puts("\n");
    uart_puts("STATUS=0x");
    uart_puthex32(status);
    uart_puts("\n");

    fingerprint = (uint16_t)((status >> 20) & 0x0FFFU);
    if (fingerprint == 0x0ACEU) {
        uart_puts("[VER] Hardware Version: 0xACE (V2.1 Patch Detected) [OK]\n");
        uart_puts("FINGERPRINT=0xACE\n");
    } else {
        uart_puts("[ERR] Hardware Fingerprint MISMATCH! Expected 0xACE, got 0x");
        uart_puthex8((uint8_t)((fingerprint >> 4) & 0xFFU));
        uart_puthex8((uint8_t)(fingerprint & 0xFFU));
        uart_puts("\n[ERR] BITSTREAM IS OUTDATED! Vivado is using old cache.\n");
        uart_puts("FINGERPRINT=0x");
        uart_puthex8((uint8_t)((fingerprint >> 4) & 0xFFU));
        uart_puthex8((uint8_t)(fingerprint & 0xFFU));
        uart_puts("\n");
    }

    rd_ptr = (uint8_t)((status >> 2) & 0x0FU);
    wr_ptr = (uint8_t)((status >> 6) & 0x0FU);
    f_empty = (uint8_t)((status >> 10) & 0x01U);
    f_full = (uint8_t)((status >> 11) & 0x01U);

    uart_puts("[DBG] PBM FIFO: wr_ptr=");
    uart_puthex8(wr_ptr);
    uart_puts(", rd_ptr=");
    uart_puthex8(rd_ptr);
    uart_puts(", empty=");
    uart_puthex8(f_empty);
    uart_puts(", full=");
    uart_puthex8(f_full);
    uart_puts("\n");

    if (f_empty == 0U) {
        uart_puts("[WRN] PBM FIFO reports NOT EMPTY at start. Check RESET path!\n");
    }

    diag_mark('5');
    if (SKIP_CRYPTO_TESTS == 0) {
        uart_puts("[DIAG] Starting AES encrypt test...\n");
        test_aes_encrypt();
        diag_mark('6');

        uart_puts("[DIAG] Starting AES decrypt test...\n");
        test_aes_decrypt();
        diag_mark('7');

        uart_puts("[DIAG] Starting SM4 test...\n");
        test_sm4_all();
        diag_mark('8');

        uart_puts("[DIAG] Starting security test...\n");
        test_security_robustness();
        diag_mark('9');
    } else {
        uart_puts("[DIAG] SKIP_CRYPTO_TESTS=1, skipping all crypto tests.\n");
    }

    uart_puts("\n[ALL TESTS FINISHED]\n");
    diag_mark('!');
    while (1) {
    }

    return 0;
}
