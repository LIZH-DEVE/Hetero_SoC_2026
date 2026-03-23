#include <stdint.h>
#include <string.h>

#ifndef UDP_GATEWAY_SMOKE_ONLY_BUILD
#define UDP_GATEWAY_SMOKE_ONLY_BUILD 0
#endif

#if !UDP_GATEWAY_SMOKE_ONLY_BUILD
#include "lwip/err.h"
#include "lwip/ip_addr.h"
#include "lwip/pbuf.h"
#include "lwip/udp.h"
#endif
#include "xparameters.h"
#include "xil_io.h"
#include "xil_mmu.h"
#include "xil_printf.h"
#include "xuartps.h"
#include "xuartps_hw.h"
#include "xtime_l.h"

#include "udp_crypto_gateway.h"

#define GATEWAY_UDP_PORT_AES 4660U
#define GATEWAY_UDP_PORT_SM4 4661U
#define GATEWAY_UDP_PORT_CTRL 4662U
#define GATEWAY_QUEUE_DEPTH 4U
#define GATEWAY_MAX_SESSIONS 4U
#define GATEWAY_BLOCK_BYTES 16U
#define GATEWAY_MAX_PAYLOAD_BYTES 1472U
#define GATEWAY_MAX_CONTROL_PAYLOAD_BYTES 64U
#define GATEWAY_WAIT_ENGINE_POLLS 100000U
#define GATEWAY_WAIT_BLOCK_POLLS 100000U
#define GATEWAY_WAIT_TX_WORD_POLLS 10000U
#define GATEWAY_MAX_STALE_DRAIN_WORDS 8U
#define GATEWAY_VERBOSE_BLOCK_LOG_BYTES 64U
#define GATEWAY_PROGRESS_LOG_BYTES 256U
#define GATEWAY_AUTH_FAILURE_THRESHOLD 3U
#define GATEWAY_REPLAY_FAILURE_THRESHOLD 3U
#define GATEWAY_BINDING_ID_DEFAULT 0x41583702U
#define GATEWAY_ALGO_FLAG_AES 0x01U
#define GATEWAY_ALGO_FLAG_SM4 0x02U
#define GATEWAY_BENCH_RECORD_COUNT 5U
#define GATEWAY_STATUS_WORD_COUNT 14U
#define GATEWAY_CONTROL_HEADER_BYTES 24U
#define GATEWAY_STATUS_PAYLOAD_BYTES (GATEWAY_STATUS_WORD_COUNT * 4U)
#define GATEWAY_BENCH_HEADER_BYTES 4U
#define GATEWAY_BENCH_RECORD_BYTES 12U
#define GATEWAY_DEFAULT_BENCH_REPEATS 8U

#define SLCR_UNLOCK_ADDR 0xF8000008U
#define SLCR_LOCK_ADDR   0xF8000004U
#define SLCR_UNLOCK_KEY  0x0000DF0DU
#define SLCR_LOCK_KEY    0x0000767BU

#define IO_PLL_CTRL_ADDR       0xF8000108U
#define IO_PLL_STATUS_ADDR     0xF800010CU
#define IO_PLL_CFG_ADDR        0xF8000118U
#define GEM0_RCLK_CTRL_ADDR    0xF8000138U
#define GEM0_CLK_CTRL_ADDR     0xF8000140U
#define TRACE_CLK_CTRL_ADDR    0xF8000168U
#define FPGA0_CLK_CTRL_ADDR    0xF8000170U
#define FPGA_CLK621_TRUE_ADDR  0xF80001C4U
#define FPGA_RST_CTRL_ADDR     0xF8000240U
#define FPGA_LVL_SHIFTER_ADDR  0xF8000900U
#define CUSTOM_UART_INPUT_CLK_HZ 160000000U
#define SMOKE_UART_DRAIN_TIMEOUT 1000000U
#define SMOKE_KEY_PATTERN_10 0xDEADBEEFU
#define SMOKE_KEY_PATTERN_10_FLIP 0x21524110U
#define SMOKE_KEY_PATTERN_14 0xA5C3F17EU
#define SMOKE_KEY_PATTERN_14_FLIP 0x5A3C0E81U
#define SMOKE_KEY_PATTERN_18 0x1BADB002U
#define SMOKE_KEY_PATTERN_18_FLIP 0xE4524FFDU
#define SMOKE_KEY_PATTERN_1C 0xC001D00DU
#define SMOKE_KEY_PATTERN_1C_FLIP 0x3FFE2FF2U
#define SMOKE_AES_CTRL_WORD 0x00000002U
#define SMOKE_STATUS_TIMEOUT_CTRL_READY 100000U
#define SMOKE_STATUS_TIMEOUT_BLOCK_DONE 100000U
#define SMOKE_STATUS_TIMEOUT_TX_WORD 10000U
#define SMOKE_MAX_DRAIN_WORDS 8U

#if defined(XPAR_CRYPTO_ACCEL_AXI_0_BASEADDR)
#define CRYPTO_BASE_ADDR XPAR_CRYPTO_ACCEL_AXI_0_BASEADDR
#else
#define CRYPTO_BASE_ADDR 0x43C00000U
#define CRYPTO_BASE_FALLBACK 1
#endif

#if defined(XPAR_DMA_SUBSYSTEM_V2_WRAPPER_0_BASEADDR)
#define WRAPPER_BASE_ADDR XPAR_DMA_SUBSYSTEM_V2_WRAPPER_0_BASEADDR
#else
#define WRAPPER_BASE_ADDR 0x40000000U
#define WRAPPER_BASE_FALLBACK 1
#endif

#define REG_CTRL      0x00U
#define REG_DATA_IN   0x04U
#define REG_STATUS    0x08U
#define REG_DATA_OUT  0x0CU
#define REG_KEY_0     0x10U

#define WRAP_REG_CTRL                 0x00U
#define WRAP_REG_STATUS               0x04U
#define WRAP_REG_BASE_ADDR            0x08U
#define WRAP_REG_LEN                  0x0CU
#define WRAP_REG_S2MM_ADDR            0x20U
#define WRAP_REG_S2MM_DATA            0x24U
#define WRAP_REG_KEY0                 0x28U
#define WRAP_REG_KEY3                 0x34U
#define WRAP_REG_LOOPBACK_MODE        0x48U
#define WRAP_REG_RING_BASE            0x50U
#define WRAP_REG_RING_HEAD            0x54U
#define WRAP_REG_RING_TAIL            0x58U
#define WRAP_REG_RING_SIZE            0x5CU
#define WRAP_REG_NET_CFG0             0x90U
#define WRAP_REG_NET_LOCAL_IP         0x94U
#define WRAP_REG_NET_LOCAL_MAC_LO     0x98U
#define WRAP_REG_NET_LOCAL_MAC_HI     0x9CU
#define WRAP_REG_INJ_CTRL             0xA0U
#define WRAP_REG_INJ_DATA             0xA4U
#define WRAP_REG_INJ_STATUS           0xA8U
#define WRAP_REG_TXCAP_CTRL           0xACU
#define WRAP_REG_TXCAP_STATUS         0xB0U
#define WRAP_REG_TXCAP_DATA           0xB4U
#define WRAP_REG_NETDBG_STATUS        0xB8U
#define WRAP_REG_NET_APPLIED_CFG0     0xBCU
#define WRAP_REG_NET_APPLIED_LOCAL_IP 0xC0U
#define WRAP_REG_NET_APPLIED_MAC_LO   0xC4U
#define WRAP_REG_NET_APPLIED_MAC_HI   0xC8U

#define STATUS_SYS_READY 0x00000001U
#define STATUS_TX_EMPTY  0x00000002U

#define ALGO_AES      0U
#define ALGO_SM4      1U
#define MODE_ENCRYPT  1U
#define GATEWAY_CTRL_WORD_AES ((ALGO_AES & 0x01U) | ((uint32_t)MODE_ENCRYPT << 1))
#define GATEWAY_CTRL_WORD_SM4 ((ALGO_SM4 & 0x01U) | ((uint32_t)MODE_ENCRYPT << 1))

#define GATEWAY_CTRL_MAGIC   0x4352544CU
#define GATEWAY_CTRL_VERSION 1U

#define GATEWAY_CTRL_MSG_HELLO   1U
#define GATEWAY_CTRL_MSG_SET_KEY 2U
#define GATEWAY_CTRL_MSG_LOCK    3U
#define GATEWAY_CTRL_MSG_UNLOCK  4U
#define GATEWAY_CTRL_MSG_STATUS  5U
#define GATEWAY_CTRL_MSG_BENCH   6U

#define GATEWAY_CTRL_STATUS_OK               0U
#define GATEWAY_CTRL_STATUS_BAD_MAGIC        1U
#define GATEWAY_CTRL_STATUS_BAD_VERSION      2U
#define GATEWAY_CTRL_STATUS_BAD_LENGTH       3U
#define GATEWAY_CTRL_STATUS_SESSION_REQUIRED 4U
#define GATEWAY_CTRL_STATUS_AUTH_FAIL        5U
#define GATEWAY_CTRL_STATUS_REPLAY           6U
#define GATEWAY_CTRL_STATUS_LOCKED           7U
#define GATEWAY_CTRL_STATUS_NO_SESSION       8U
#define GATEWAY_CTRL_STATUS_INTERNAL         9U
#define GATEWAY_CTRL_STATUS_UNKNOWN_MSG      10U
#define GATEWAY_CTRL_STATUS_NOT_AUTHORIZED   11U
#define GATEWAY_CTRL_STATUS_BUSY             12U

#define HW_WRITE(offset, data) Xil_Out32(CRYPTO_BASE_ADDR + (offset), (data))
#define HW_READ(offset)        Xil_In32(CRYPTO_BASE_ADDR + (offset))

#if !UDP_GATEWAY_SMOKE_ONLY_BUILD
typedef enum {
    GATEWAY_ALGO_AES = 0,
    GATEWAY_ALGO_SM4 = 1
} gateway_algo_t;

typedef struct {
    gateway_algo_t algo;
    struct udp_pcb *reply_pcb;
    ip_addr_t remote_ip;
    uint16_t remote_port;
    uint16_t payload_len;
    uint16_t offset;
    uint32_t session_id;
    uint8_t key_loaded;
    uint8_t ctrl_armed;
    uint8_t effective_key[16];
    uint8_t payload[GATEWAY_MAX_PAYLOAD_BYTES];
    uint8_t ciphertext[GATEWAY_MAX_PAYLOAD_BYTES];
} gateway_request_t;

typedef enum {
    JOB_IDLE = 0,
    JOB_WAIT_ENGINE_READY,
    JOB_LOAD_KEY,
    JOB_CONFIG_CTRL,
    JOB_WAIT_INPUT_ACCEPT,
    JOB_PUSH_BLOCK,
    JOB_WAIT_BLOCK_DONE,
    JOB_PULL_BLOCK,
    JOB_SEND_RESPONSE
} gateway_job_state_t;

typedef struct {
    gateway_algo_t algo;
    uint16_t listen_port;
} gateway_listener_context_t;

typedef struct {
    uint8_t active;
    uint8_t locked;
    uint8_t authorized_algos;
    uint8_t auth_failures;
    uint8_t replay_failures;
    uint8_t reserved[3];
    ip_addr_t remote_ip;
    uint32_t session_id;
    uint32_t binding_id;
    uint32_t highest_seq_id;
    uint32_t replay_window;
    uint8_t effective_key_aes[16];
    uint8_t effective_key_sm4[16];
} gateway_session_t;

static struct udp_pcb *g_udp_pcb_aes;
static struct udp_pcb *g_udp_pcb_sm4;
static struct udp_pcb *g_udp_pcb_ctrl;
static XUartPs g_uart;
static gateway_request_t g_queue[GATEWAY_QUEUE_DEPTH];
static gateway_session_t g_sessions[GATEWAY_MAX_SESSIONS];
static uint8_t g_queue_head;
static uint8_t g_queue_tail;
static uint8_t g_queue_count;
static gateway_request_t g_active_job;
static uint16_t g_active_offset;
static uint8_t g_job_active;
static gateway_job_state_t g_job_state = JOB_IDLE;
static uint32_t g_job_wait_cycles;
static uint32_t g_stat_drops_busy;
static uint32_t g_stat_drops_invalid;
static uint32_t g_stat_completed;
static uint32_t g_stat_jobs_started;
static uint32_t g_stat_failures;
static uint32_t g_stat_rx_ctrl_ok;
static uint32_t g_stat_rx_data_ok;
static uint32_t g_stat_tx_ok;
static uint32_t g_stat_drop_unauthorized;
static uint32_t g_stat_drop_replay;
static uint32_t g_stat_bind_fail;
static uint32_t g_stat_lock_events;
static uint32_t g_stat_crypto_timeout;
static uint32_t g_stat_crypto_fail;
static uint32_t g_next_session_id = 1U;
static uint8_t g_active_words_pushed;
static uint8_t g_active_words_pulled;
static uint8_t g_bench_input[GATEWAY_MAX_PAYLOAD_BYTES];
static uint8_t g_bench_sw_output[GATEWAY_MAX_PAYLOAD_BYTES];
static uint8_t g_bench_hw_output[GATEWAY_MAX_PAYLOAD_BYTES];
static const gateway_listener_context_t g_listener_aes = { GATEWAY_ALGO_AES, GATEWAY_UDP_PORT_AES };
static const gateway_listener_context_t g_listener_sm4 = { GATEWAY_ALGO_SM4, GATEWAY_UDP_PORT_SM4 };

static const char *job_state_name(gateway_job_state_t state)
{
    switch (state) {
    case JOB_IDLE:
        return "IDLE";
    case JOB_WAIT_ENGINE_READY:
        return "WAIT_ENGINE_READY";
    case JOB_LOAD_KEY:
        return "LOAD_KEY";
    case JOB_CONFIG_CTRL:
        return "CONFIG_CTRL";
    case JOB_WAIT_INPUT_ACCEPT:
        return "WAIT_INPUT_ACCEPT";
    case JOB_PUSH_BLOCK:
        return "PUSH_BLOCK";
    case JOB_WAIT_BLOCK_DONE:
        return "WAIT_BLOCK_DONE";
    case JOB_PULL_BLOCK:
        return "PULL_BLOCK";
    case JOB_SEND_RESPONSE:
        return "SEND_RESPONSE";
    default:
        return "UNKNOWN";
    }
}
#else
static XUartPs g_uart;
#endif

static void mask_write32(uint32_t addr, uint32_t mask, uint32_t value)
{
    uint32_t cur = Xil_In32(addr);
    cur &= ~mask;
    cur |= (value & mask);
    Xil_Out32(addr, cur);
}

static int poll_mask32(uint32_t addr, uint32_t mask, uint32_t expected, uint32_t timeout_cycles)
{
    while (timeout_cycles-- > 0U) {
        if ((Xil_In32(addr) & mask) == expected) {
            return 0;
        }
    }

    return -1;
}

static void enable_custom_pl_path(void)
{
    Xil_Out32(SLCR_UNLOCK_ADDR, SLCR_UNLOCK_KEY);

    /*
     * Route A: keep the stable official-FSBL boot path, but patch in the
     * minimum custom PS clock/profile needed by the PL AXI fabric.
     *
     * Differences extracted from the custom ps7_init:
     *   IO PLL    : 0xF8000118 = 0x000FA240, 0xF8000108[18:12] = 0x30
     *   GEM0 RCLK : 0xF8000138 = 0x00000011
     *   GEM0 CLK  : 0xF8000140 = 0x00100141
     *   TRACE CLK : 0xF8000168 = 0x00000801
     *   FPGA0 CLK : 0xF8000170 = 0x00400800
     */
    mask_write32(IO_PLL_CFG_ADDR,  0x003FFFF0U, 0x000FA240U);
    mask_write32(IO_PLL_CTRL_ADDR, 0x0007F000U, 0x00030000U);
    mask_write32(IO_PLL_CTRL_ADDR, 0x00000010U, 0x00000010U);
    mask_write32(IO_PLL_CTRL_ADDR, 0x00000001U, 0x00000001U);
    mask_write32(IO_PLL_CTRL_ADDR, 0x00000001U, 0x00000000U);
    if (poll_mask32(IO_PLL_STATUS_ADDR, 0x00000004U, 0x00000004U, 10000000U) != 0) {
        xil_printf("udp_crypto_gateway: IO PLL relock timeout status=0x%08lx\r\n",
                   (unsigned long)Xil_In32(IO_PLL_STATUS_ADDR));
    }
    mask_write32(IO_PLL_CTRL_ADDR, 0x00000010U, 0x00000000U);

    mask_write32(GEM0_RCLK_CTRL_ADDR, 0x00000011U, 0x00000011U);
    mask_write32(GEM0_CLK_CTRL_ADDR,  0x03F03F71U, 0x00100141U);
    mask_write32(TRACE_CLK_CTRL_ADDR, 0x00003F31U, 0x00000801U);
    mask_write32(FPGA0_CLK_CTRL_ADDR, 0x03F03F30U, 0x00400800U);
    mask_write32(FPGA_CLK621_TRUE_ADDR, 0x00000001U, 0x00000001U);
    mask_write32(FPGA_LVL_SHIFTER_ADDR, 0x0000000FU, 0x0000000FU);
    mask_write32(FPGA_RST_CTRL_ADDR, 0xFFFFFFFFU, 0x00000000U);
    Xil_Out32(SLCR_LOCK_ADDR, SLCR_LOCK_KEY);
}

static void reinit_diag_uart(void)
{
    XUartPs_Config *cfg;
    int status;

    cfg = XUartPs_LookupConfig(XPAR_XUARTPS_0_DEVICE_ID);
    if (cfg == NULL) {
        return;
    }

    status = XUartPs_CfgInitialize(&g_uart, cfg, cfg->BaseAddress);
    if (status != XST_SUCCESS) {
        return;
    }

    /*
     * Route A changes IO PLL from the official profile to the custom one.
     * UART1 clock divider stays unchanged, so the effective UART input clock
     * moves from 100 MHz to 160 MHz. The BSP still bakes in 100 MHz, so
     * force the real post-patch clock before recomputing 115200 baud.
     */
    g_uart.Config.InputClockHz = CUSTOM_UART_INPUT_CLK_HZ;
    XUartPs_SetOperMode(&g_uart, XUARTPS_OPER_MODE_NORMAL);
    (void)XUartPs_SetBaudRate(&g_uart, 115200U);
}

static void dump_pl_registers(void)
{
    uint32_t val;
    int i;
    static const uint32_t wrapper_probe_offsets[] = {
        WRAP_REG_CTRL,
        WRAP_REG_STATUS,
        WRAP_REG_BASE_ADDR,
        WRAP_REG_LEN,
        WRAP_REG_S2MM_ADDR,
        WRAP_REG_S2MM_DATA,
        WRAP_REG_KEY0,
        WRAP_REG_KEY3,
        WRAP_REG_LOOPBACK_MODE,
        WRAP_REG_RING_BASE,
        WRAP_REG_RING_HEAD,
        WRAP_REG_RING_TAIL,
        WRAP_REG_RING_SIZE,
        WRAP_REG_NET_CFG0,
        WRAP_REG_NET_LOCAL_IP,
        WRAP_REG_NET_LOCAL_MAC_LO,
        WRAP_REG_NET_LOCAL_MAC_HI,
        WRAP_REG_INJ_CTRL,
        WRAP_REG_INJ_DATA,
        WRAP_REG_INJ_STATUS,
        WRAP_REG_TXCAP_CTRL,
        WRAP_REG_TXCAP_STATUS,
        WRAP_REG_TXCAP_DATA,
        WRAP_REG_NETDBG_STATUS,
        WRAP_REG_NET_APPLIED_CFG0,
        WRAP_REG_NET_APPLIED_LOCAL_IP,
        WRAP_REG_NET_APPLIED_MAC_LO,
        WRAP_REG_NET_APPLIED_MAC_HI
    };

    /* ===== SLCR PL registers (PS-side: clock/reset/level-shifter) ===== */
    xil_printf("\r\n===== SLCR PL Diagnostics =====\r\n");

    val = Xil_In32(IO_PLL_CTRL_ADDR);
    xil_printf("IO_PLL_CTRL     (0xF8000108) = 0x%08lx\r\n", (unsigned long)val);

    val = Xil_In32(IO_PLL_STATUS_ADDR);
    xil_printf("IO_PLL_STATUS   (0xF800010C) = 0x%08lx\r\n", (unsigned long)val);

    val = Xil_In32(IO_PLL_CFG_ADDR);
    xil_printf("IO_PLL_CFG      (0xF8000118) = 0x%08lx\r\n", (unsigned long)val);

    val = Xil_In32(GEM0_RCLK_CTRL_ADDR);
    xil_printf("GEM0_RCLK_CTRL  (0xF8000138) = 0x%08lx\r\n", (unsigned long)val);

    val = Xil_In32(GEM0_CLK_CTRL_ADDR);
    xil_printf("GEM0_CLK_CTRL   (0xF8000140) = 0x%08lx\r\n", (unsigned long)val);

    val = Xil_In32(TRACE_CLK_CTRL_ADDR);
    xil_printf("TRACE_CLK_CTRL  (0xF8000168) = 0x%08lx\r\n", (unsigned long)val);

    val = Xil_In32(0xF8000170U);
    xil_printf("FPGA0_CLK_CTRL  (0xF8000170) = 0x%08lx\r\n", (unsigned long)val);

    val = Xil_In32(0xF80001C4U);
    xil_printf("FPGA_CLK621     (0xF80001C4) = 0x%08lx\r\n", (unsigned long)val);

    val = Xil_In32(0xF8000240U);
    xil_printf("FPGA_RST_CTRL   (0xF8000240) = 0x%08lx\r\n", (unsigned long)val);

    val = Xil_In32(0xF8000900U);
    xil_printf("LVL_SHIFTERS_EN (0xF8000900) = 0x%08lx\r\n", (unsigned long)val);

    /* DEVCFG STATUS: bit2 = PCFG_DONE (PL configured?) */
    val = Xil_In32(0xF8007014U);
    xil_printf("DEVCFG_STATUS   (0xF8007014) = 0x%08lx\r\n", (unsigned long)val);
    xil_printf("  PCFG_DONE = %u\r\n", (unsigned)((val >> 2) & 1U));

    xil_printf("\r\n===== Active MMIO Bases =====\r\n");
    xil_printf("CRYPTO_BASE_ADDR  = 0x%08lx", (unsigned long)CRYPTO_BASE_ADDR);
#ifdef CRYPTO_BASE_FALLBACK
    xil_printf(" (fallback)");
#endif
    xil_printf("\r\n");
    xil_printf("WRAPPER_BASE_ADDR = 0x%08lx", (unsigned long)WRAPPER_BASE_ADDR);
#ifdef WRAPPER_BASE_FALLBACK
    xil_printf(" (fallback)");
#endif
    xil_printf("\r\n");

    /* ===== Crypto IP raw dump: 0x43C00000 ~ 0x43C0003C ===== */
    xil_printf("\r\n===== Crypto MMIO Raw Dump (0x%08lx) =====\r\n",
               (unsigned long)CRYPTO_BASE_ADDR);
    for (i = 0; i < 16; ++i) {
        uint32_t addr = CRYPTO_BASE_ADDR + (uint32_t)(i * 4);
        val = Xil_In32(addr);
        xil_printf("  [0x%08lx] = 0x%08lx\r\n", (unsigned long)addr, (unsigned long)val);
    }

    /* ===== Wrapper probe: read non-zero-default and applied-status CSRs ===== */
    xil_printf("\r\n===== Wrapper CSR Probe (0x%08lx) =====\r\n",
               (unsigned long)WRAPPER_BASE_ADDR);
    for (i = 0; i < (int)(sizeof(wrapper_probe_offsets) / sizeof(wrapper_probe_offsets[0])); ++i) {
        uint32_t addr = WRAPPER_BASE_ADDR + wrapper_probe_offsets[i];
        val = Xil_In32(addr);
        xil_printf("  [0x%08lx] = 0x%08lx\r\n", (unsigned long)addr, (unsigned long)val);
    }

    xil_printf("===== End Register Dump =====\r\n\r\n");
}

void udp_crypto_gateway_early_platform_prepare(void)
{
    enable_custom_pl_path();
}

void udp_crypto_gateway_fix_uart_after_platform_init(void)
{
    reinit_diag_uart();
}

static void reset_job_wait_debug(void)
{
#if !UDP_GATEWAY_SMOKE_ONLY_BUILD
    g_job_wait_cycles = 0U;
#endif
}

#if !UDP_GATEWAY_SMOKE_ONLY_BUILD
static const uint32_t g_gateway_aes_key_offsets[4] = {
    REG_KEY_0 + 0x0CU,
    REG_KEY_0 + 0x08U,
    REG_KEY_0 + 0x04U,
    REG_KEY_0 + 0x00U
};

static const uint32_t g_gateway_sm4_key_offsets[4] = {
    REG_KEY_0 + 0x0CU,
    REG_KEY_0 + 0x08U,
    REG_KEY_0 + 0x04U,
    REG_KEY_0 + 0x00U
};

static const char *gateway_algo_name(gateway_algo_t algo)
{
    return (algo == GATEWAY_ALGO_SM4) ? "SM4" : "AES";
}

static uint16_t gateway_reply_local_port(const gateway_request_t *job)
{
    if ((job == NULL) || (job->reply_pcb == NULL)) {
        return 0U;
    }
    return job->reply_pcb->local_port;
}

static uint32_t gateway_ctrl_word(gateway_algo_t algo)
{
    return (algo == GATEWAY_ALGO_SM4) ? GATEWAY_CTRL_WORD_SM4 : GATEWAY_CTRL_WORD_AES;
}

static uint32_t gateway_load_be_word(const uint8_t *data);
static void smoke_write32(uint32_t offset, uint32_t value);
static int gateway_log_block_details(const gateway_request_t *job);
static int gateway_should_log_progress(const gateway_request_t *job, uint16_t next_offset);

static void gateway_load_key_to_hw(const gateway_request_t *job)
{
    const uint32_t *key_offsets = (job->algo == GATEWAY_ALGO_SM4) ? g_gateway_sm4_key_offsets : g_gateway_aes_key_offsets;
    uint32_t i;
    int verbose = gateway_log_block_details(job);

    for (i = 0U; i < 4U; ++i) {
        uint32_t key_word = gateway_load_be_word(&job->effective_key[i * 4U]);
        if (verbose || (i == 0U)) {
            xil_printf("udp_crypto_gateway: load_key algo=%s[%lu] off=0x%02lx val=0x%08lx\r\n",
                       gateway_algo_name(job->algo),
                       (unsigned long)i,
                       (unsigned long)key_offsets[i],
                       (unsigned long)key_word);
        }
        smoke_write32(key_offsets[i], key_word);
    }
}
#endif

static const char *direct_smoke_case_name(unsigned case_id)
{
    switch (case_id) {
    case 1U:
        return "read_only";
    case 2U:
        return "write_key_10_flip";
    case 3U:
        return "write_key_14_flip";
    case 4U:
        return "write_key_18_flip";
    case 5U:
        return "write_key_1c_flip";
    case 6U:
        return "write_ctrl_safe";
    case 7U:
        return "aes_block_smoke_enc";
    default:
        return "unknown";
    }
}

static void smoke_print_status_line(const char *label, uint32_t value)
{
    xil_printf("%s0x%08lx\r\n", label, (unsigned long)value);
}

static void smoke_print_word_vector(const char *label, const uint32_t *words, uint32_t word_count)
{
    uint32_t i;

    for (i = 0U; i < word_count; ++i) {
        xil_printf("%s[%lu] = 0x%08lx\r\n",
                   label,
                   (unsigned long)i,
                   (unsigned long)words[i]);
    }
}

static void smoke_prepare_mmio_region(void)
{
    static uint8_t prepared;

    if (prepared != 0U) {
        return;
    }

    Xil_SetTlbAttributes((INTPTR)CRYPTO_BASE_ADDR, STRONG_ORDERED);
    Xil_SetTlbAttributes((INTPTR)WRAPPER_BASE_ADDR, STRONG_ORDERED);
    DATA_SYNC;
    INST_SYNC;
    prepared = 1U;
}

static void smoke_uart_drain(void)
{
    uint32_t timeout_cycles = SMOKE_UART_DRAIN_TIMEOUT;

    while (timeout_cycles-- > 0U) {
        uint32_t sr = Xil_In32((UINTPTR)XPAR_XUARTPS_0_BASEADDR + XUARTPS_SR_OFFSET);
        if (((sr & XUARTPS_SR_TXEMPTY) != 0U) && ((sr & XUARTPS_SR_TACTIVE) == 0U)) {
            break;
        }
    }
}

static uint32_t smoke_read32(uint32_t offset)
{
    DATA_SYNC;
    INST_SYNC;
    return HW_READ(offset);
}

static void smoke_write32(uint32_t offset, uint32_t value)
{
    DATA_SYNC;
    HW_WRITE(offset, value);
    DATA_SYNC;
    INST_SYNC;
}

#if !UDP_GATEWAY_SMOKE_ONLY_BUILD
static uint32_t gateway_load_be_word(const uint8_t *data)
{
    return ((uint32_t)data[0] << 24) |
           ((uint32_t)data[1] << 16) |
           ((uint32_t)data[2] << 8) |
           (uint32_t)data[3];
}

static void gateway_store_be_word(uint8_t *out, uint32_t word)
{
    out[0] = (uint8_t)((word >> 24) & 0xFFU);
    out[1] = (uint8_t)((word >> 16) & 0xFFU);
    out[2] = (uint8_t)((word >> 8) & 0xFFU);
    out[3] = (uint8_t)(word & 0xFFU);
}

static uint16_t gateway_load_be16(const uint8_t *data)
{
    return (uint16_t)(((uint16_t)data[0] << 8) | (uint16_t)data[1]);
}

static void gateway_store_be16(uint8_t *out, uint16_t value)
{
    out[0] = (uint8_t)((value >> 8) & 0xFFU);
    out[1] = (uint8_t)(value & 0xFFU);
}

static uint32_t gateway_fnv1a32_bytes(const uint8_t *data, uint32_t len, uint32_t seed)
{
    uint32_t hash = seed;
    uint32_t i;

    for (i = 0U; i < len; ++i) {
        hash ^= (uint32_t)data[i];
        hash *= 0x01000193U;
    }

    return hash;
}

static uint32_t gateway_get_device_binding_id(void)
{
    return GATEWAY_BINDING_ID_DEFAULT;
}

static void gateway_derive_effective_key(const uint8_t *user_key, uint32_t binding_id, gateway_algo_t algo, uint8_t *out_key)
{
    uint8_t material[22];
    uint32_t counter;

    memcpy(material, user_key, 16U);
    gateway_store_be_word(&material[16], binding_id);
    material[20] = (uint8_t)algo;

    for (counter = 0U; counter < 4U; ++counter) {
        uint32_t word;

        material[21] = (uint8_t)counter;
        word = gateway_fnv1a32_bytes(material, sizeof(material), 0x811C9DC5U ^ counter);
        gateway_store_be_word(&out_key[counter * 4U], word);
    }
}

static uint32_t gateway_compute_auth_tag(uint8_t msg_type,
                                         uint32_t session_id,
                                         uint32_t seq_id,
                                         uint8_t flags,
                                         uint16_t status_code,
                                         const uint8_t *payload,
                                         uint16_t payload_len,
                                         uint32_t binding_id)
{
    uint8_t header_material[20];
    uint8_t binding_material[4];
    uint32_t hash;

    gateway_store_be_word(&header_material[0], GATEWAY_CTRL_MAGIC);
    header_material[4] = GATEWAY_CTRL_VERSION;
    header_material[5] = msg_type;
    header_material[6] = flags;
    header_material[7] = 0U;
    gateway_store_be_word(&header_material[8], session_id);
    gateway_store_be_word(&header_material[12], seq_id);
    gateway_store_be16(&header_material[16], payload_len);
    gateway_store_be16(&header_material[18], status_code);

    gateway_store_be_word(binding_material, binding_id);
    hash = gateway_fnv1a32_bytes(binding_material, sizeof(binding_material), 0x811C9DC5U);
    hash = gateway_fnv1a32_bytes(header_material, sizeof(header_material), hash);
    if ((payload != NULL) && (payload_len != 0U)) {
        hash = gateway_fnv1a32_bytes(payload, payload_len, hash);
    }
    return hash;
}

static uint8_t gateway_algo_flag(gateway_algo_t algo)
{
    return (algo == GATEWAY_ALGO_SM4) ? GATEWAY_ALGO_FLAG_SM4 : GATEWAY_ALGO_FLAG_AES;
}

static const uint8_t *gateway_session_key_for_algo(const gateway_session_t *session, gateway_algo_t algo)
{
    if (session == NULL) {
        return NULL;
    }

    return (algo == GATEWAY_ALGO_SM4) ? session->effective_key_sm4 : session->effective_key_aes;
}

static int gateway_session_allows_algo(const gateway_session_t *session, gateway_algo_t algo)
{
    uint8_t required_flag;

    if ((session == NULL) || (session->active == 0U) || (session->locked != 0U)) {
        return 0;
    }

    required_flag = gateway_algo_flag(algo);
    return ((session->authorized_algos & required_flag) != 0U) ? 1 : 0;
}

static gateway_session_t *gateway_find_session_by_ip(const ip_addr_t *remote_ip)
{
    uint32_t i;

    for (i = 0U; i < GATEWAY_MAX_SESSIONS; ++i) {
        if ((g_sessions[i].active != 0U) && ip_addr_cmp(&g_sessions[i].remote_ip, remote_ip)) {
            return &g_sessions[i];
        }
    }

    return NULL;
}

static gateway_session_t *gateway_find_session_by_id(const ip_addr_t *remote_ip, uint32_t session_id)
{
    gateway_session_t *session = gateway_find_session_by_ip(remote_ip);

    if ((session == NULL) || (session->session_id != session_id)) {
        return NULL;
    }

    return session;
}

static gateway_session_t *gateway_alloc_session(const ip_addr_t *remote_ip)
{
    gateway_session_t *session = gateway_find_session_by_ip(remote_ip);
    uint32_t i;

    if (session != NULL) {
        memset(session, 0, sizeof(*session));
        session->active = 1U;
        ip_addr_copy(session->remote_ip, *remote_ip);
        session->binding_id = gateway_get_device_binding_id();
        session->session_id = g_next_session_id++;
        if (g_next_session_id == 0U) {
            g_next_session_id = 1U;
        }
        return session;
    }

    for (i = 0U; i < GATEWAY_MAX_SESSIONS; ++i) {
        if (g_sessions[i].active == 0U) {
            memset(&g_sessions[i], 0, sizeof(g_sessions[i]));
            g_sessions[i].active = 1U;
            ip_addr_copy(g_sessions[i].remote_ip, *remote_ip);
            g_sessions[i].binding_id = gateway_get_device_binding_id();
            g_sessions[i].session_id = g_next_session_id++;
            if (g_next_session_id == 0U) {
                g_next_session_id = 1U;
            }
            return &g_sessions[i];
        }
    }

    return &g_sessions[0];
}

static void gateway_zero_session_keys(gateway_session_t *session)
{
    if (session == NULL) {
        return;
    }

    memset(session->effective_key_aes, 0, sizeof(session->effective_key_aes));
    memset(session->effective_key_sm4, 0, sizeof(session->effective_key_sm4));
    session->authorized_algos = 0U;
}

static void gateway_lock_session(gateway_session_t *session)
{
    if (session == NULL) {
        return;
    }

    if (session->locked == 0U) {
        g_stat_lock_events++;
    }
    session->locked = 1U;
    gateway_zero_session_keys(session);
}

static void gateway_unlock_session(gateway_session_t *session)
{
    if (session == NULL) {
        return;
    }

    session->locked = 0U;
    session->auth_failures = 0U;
    session->replay_failures = 0U;
    session->highest_seq_id = 0U;
    session->replay_window = 0U;
}

static int gateway_check_and_update_seq(gateway_session_t *session, uint32_t seq_id)
{
    uint32_t delta;

    if ((session == NULL) || (seq_id == 0U)) {
        return -1;
    }

    if (session->highest_seq_id == 0U) {
        session->highest_seq_id = seq_id;
        session->replay_window = 1U;
        return 0;
    }

    if (seq_id > session->highest_seq_id) {
        delta = seq_id - session->highest_seq_id;
        if (delta >= 32U) {
            session->replay_window = 1U;
        } else {
            session->replay_window = (session->replay_window << delta) | 1U;
        }
        session->highest_seq_id = seq_id;
        return 0;
    }

    delta = session->highest_seq_id - seq_id;
    if (delta >= 32U) {
        return -1;
    }

    if ((session->replay_window & (1UL << delta)) != 0U) {
        return -1;
    }

    session->replay_window |= (1UL << delta);
    return 0;
}

static int gateway_control_auth_ok(gateway_session_t *session,
                                   uint8_t msg_type,
                                   uint32_t session_id,
                                   uint32_t seq_id,
                                   uint8_t flags,
                                   uint16_t status_code,
                                   const uint8_t *payload,
                                   uint16_t payload_len,
                                   uint32_t provided_auth_tag)
{
    uint32_t expected_tag;

    if (session == NULL) {
        return -1;
    }

    expected_tag = gateway_compute_auth_tag(msg_type,
                                            session_id,
                                            seq_id,
                                            flags,
                                            status_code,
                                            payload,
                                            payload_len,
                                            session->binding_id);
    return (expected_tag == provided_auth_tag) ? 0 : -1;
}

static void gateway_pack_control_header(uint8_t *out,
                                        uint8_t msg_type,
                                        uint8_t flags,
                                        uint32_t session_id,
                                        uint32_t seq_id,
                                        uint16_t payload_len,
                                        uint16_t status_code,
                                        uint32_t auth_tag)
{
    gateway_store_be_word(&out[0], GATEWAY_CTRL_MAGIC);
    out[4] = GATEWAY_CTRL_VERSION;
    out[5] = msg_type;
    out[6] = flags;
    out[7] = 0U;
    gateway_store_be_word(&out[8], session_id);
    gateway_store_be_word(&out[12], seq_id);
    gateway_store_be16(&out[16], payload_len);
    gateway_store_be16(&out[18], status_code);
    gateway_store_be_word(&out[20], auth_tag);
}

static void gateway_pack_status_payload(uint8_t *out, const gateway_session_t *session)
{
    gateway_store_be_word(&out[0], (session != NULL) ? session->binding_id : gateway_get_device_binding_id());
    gateway_store_be_word(&out[4], (session != NULL) ? session->session_id : 0U);
    gateway_store_be_word(&out[8], (session != NULL) ? (uint32_t)session->authorized_algos : 0U);
    gateway_store_be_word(&out[12], (session != NULL) ? (uint32_t)session->locked : 0U);
    gateway_store_be_word(&out[16], g_stat_rx_ctrl_ok);
    gateway_store_be_word(&out[20], g_stat_rx_data_ok);
    gateway_store_be_word(&out[24], g_stat_tx_ok);
    gateway_store_be_word(&out[28], g_stat_drops_invalid);
    gateway_store_be_word(&out[32], g_stat_drop_unauthorized);
    gateway_store_be_word(&out[36], g_stat_drop_replay);
    gateway_store_be_word(&out[40], g_stat_bind_fail);
    gateway_store_be_word(&out[44], g_stat_lock_events);
    gateway_store_be_word(&out[48], g_stat_crypto_timeout);
    gateway_store_be_word(&out[52], g_stat_crypto_fail);
}

static void gateway_send_control_response(struct udp_pcb *pcb,
                                          const ip_addr_t *addr,
                                          uint16_t port,
                                          uint8_t msg_type,
                                          uint8_t flags,
                                          uint32_t session_id,
                                          uint32_t seq_id,
                                          uint16_t status_code,
                                          const uint8_t *payload,
                                          uint16_t payload_len,
                                          uint32_t binding_id)
{
    struct pbuf *resp;
    uint8_t buffer[24U + GATEWAY_MAX_CONTROL_PAYLOAD_BYTES];
    uint32_t auth_tag = 0U;

    if (payload_len > GATEWAY_MAX_CONTROL_PAYLOAD_BYTES) {
        payload_len = GATEWAY_MAX_CONTROL_PAYLOAD_BYTES;
    }

    if (msg_type != GATEWAY_CTRL_MSG_HELLO) {
        auth_tag = gateway_compute_auth_tag(msg_type,
                                            session_id,
                                            seq_id,
                                            flags,
                                            status_code,
                                            payload,
                                            payload_len,
                                            binding_id);
    }

    gateway_pack_control_header(buffer,
                                msg_type,
                                flags,
                                session_id,
                                seq_id,
                                payload_len,
                                status_code,
                                auth_tag);
    if ((payload != NULL) && (payload_len != 0U)) {
        memcpy(&buffer[24], payload, payload_len);
    }

    resp = pbuf_alloc(PBUF_TRANSPORT, (u16_t)(24U + payload_len), PBUF_RAM);
    if (resp == NULL) {
        return;
    }

    if (pbuf_take(resp, buffer, (u16_t)(24U + payload_len)) == ERR_OK) {
        if (udp_sendto(pcb, resp, addr, port) == ERR_OK) {
            g_stat_tx_ok++;
        }
    }
    pbuf_free(resp);
}

static void clear_active_job_state(void)
{
    memset(&g_active_job, 0, sizeof(g_active_job));
    g_active_offset = 0U;
    g_job_active = 0U;
    g_job_state = JOB_IDLE;
    g_active_words_pushed = 0U;
    g_active_words_pulled = 0U;
    reset_job_wait_debug();
}

static int gateway_log_block_details(const gateway_request_t *job)
{
    return (job != NULL) && (job->payload_len <= GATEWAY_VERBOSE_BLOCK_LOG_BYTES);
}

static int gateway_should_log_progress(const gateway_request_t *job, uint16_t next_offset)
{
    if ((job == NULL) || gateway_log_block_details(job)) {
        return 0;
    }

    if ((next_offset >= job->payload_len) || ((next_offset % GATEWAY_PROGRESS_LOG_BYTES) == 0U)) {
        return 1;
    }

    return 0;
}

static const uint16_t g_gateway_bench_lengths[GATEWAY_BENCH_RECORD_COUNT] = {
    16U, 32U, 128U, 512U, 1472U
};

static const uint8_t g_gateway_bench_aes_block[16] = {
    0x32U, 0x43U, 0xF6U, 0xA8U, 0x88U, 0x5AU, 0x30U, 0x8DU,
    0x31U, 0x31U, 0x98U, 0xA2U, 0xE0U, 0x37U, 0x07U, 0x34U
};

static const uint8_t g_gateway_bench_sm4_block[16] = {
    0x01U, 0x23U, 0x45U, 0x67U, 0x89U, 0xABU, 0xCDU, 0xEFU,
    0xFEU, 0xDCU, 0xBAU, 0x98U, 0x76U, 0x54U, 0x32U, 0x10U
};

static const uint8_t g_gateway_aes_sbox[256] = {
    0x63U, 0x7CU, 0x77U, 0x7BU, 0xF2U, 0x6BU, 0x6FU, 0xC5U, 0x30U, 0x01U, 0x67U, 0x2BU, 0xFEU, 0xD7U, 0xABU, 0x76U,
    0xCAU, 0x82U, 0xC9U, 0x7DU, 0xFAU, 0x59U, 0x47U, 0xF0U, 0xADU, 0xD4U, 0xA2U, 0xAFU, 0x9CU, 0xA4U, 0x72U, 0xC0U,
    0xB7U, 0xFDU, 0x93U, 0x26U, 0x36U, 0x3FU, 0xF7U, 0xCCU, 0x34U, 0xA5U, 0xE5U, 0xF1U, 0x71U, 0xD8U, 0x31U, 0x15U,
    0x04U, 0xC7U, 0x23U, 0xC3U, 0x18U, 0x96U, 0x05U, 0x9AU, 0x07U, 0x12U, 0x80U, 0xE2U, 0xEBU, 0x27U, 0xB2U, 0x75U,
    0x09U, 0x83U, 0x2CU, 0x1AU, 0x1BU, 0x6EU, 0x5AU, 0xA0U, 0x52U, 0x3BU, 0xD6U, 0xB3U, 0x29U, 0xE3U, 0x2FU, 0x84U,
    0x53U, 0xD1U, 0x00U, 0xEDU, 0x20U, 0xFCU, 0xB1U, 0x5BU, 0x6AU, 0xCBU, 0xBEU, 0x39U, 0x4AU, 0x4CU, 0x58U, 0xCFU,
    0xD0U, 0xEFU, 0xAAU, 0xFBU, 0x43U, 0x4DU, 0x33U, 0x85U, 0x45U, 0xF9U, 0x02U, 0x7FU, 0x50U, 0x3CU, 0x9FU, 0xA8U,
    0x51U, 0xA3U, 0x40U, 0x8FU, 0x92U, 0x9DU, 0x38U, 0xF5U, 0xBCU, 0xB6U, 0xDAU, 0x21U, 0x10U, 0xFFU, 0xF3U, 0xD2U,
    0xCDU, 0x0CU, 0x13U, 0xECU, 0x5FU, 0x97U, 0x44U, 0x17U, 0xC4U, 0xA7U, 0x7EU, 0x3DU, 0x64U, 0x5DU, 0x19U, 0x73U,
    0x60U, 0x81U, 0x4FU, 0xDCU, 0x22U, 0x2AU, 0x90U, 0x88U, 0x46U, 0xEEU, 0xB8U, 0x14U, 0xDEU, 0x5EU, 0x0BU, 0xDBU,
    0xE0U, 0x32U, 0x3AU, 0x0AU, 0x49U, 0x06U, 0x24U, 0x5CU, 0xC2U, 0xD3U, 0xACU, 0x62U, 0x91U, 0x95U, 0xE4U, 0x79U,
    0xE7U, 0xC8U, 0x37U, 0x6DU, 0x8DU, 0xD5U, 0x4EU, 0xA9U, 0x6CU, 0x56U, 0xF4U, 0xEAU, 0x65U, 0x7AU, 0xAEU, 0x08U,
    0xBAU, 0x78U, 0x25U, 0x2EU, 0x1CU, 0xA6U, 0xB4U, 0xC6U, 0xE8U, 0xDDU, 0x74U, 0x1FU, 0x4BU, 0xBDU, 0x8BU, 0x8AU,
    0x70U, 0x3EU, 0xB5U, 0x66U, 0x48U, 0x03U, 0xF6U, 0x0EU, 0x61U, 0x35U, 0x57U, 0xB9U, 0x86U, 0xC1U, 0x1DU, 0x9EU,
    0xE1U, 0xF8U, 0x98U, 0x11U, 0x69U, 0xD9U, 0x8EU, 0x94U, 0x9BU, 0x1EU, 0x87U, 0xE9U, 0xCEU, 0x55U, 0x28U, 0xDFU,
    0x8CU, 0xA1U, 0x89U, 0x0DU, 0xBFU, 0xE6U, 0x42U, 0x68U, 0x41U, 0x99U, 0x2DU, 0x0FU, 0xB0U, 0x54U, 0xBBU, 0x16U
};

static const uint8_t g_gateway_sm4_sbox[256] = {
    0xD6U, 0x90U, 0xE9U, 0xFEU, 0xCCU, 0xE1U, 0x3DU, 0xB7U, 0x16U, 0xB6U, 0x14U, 0xC2U, 0x28U, 0xFBU, 0x2CU, 0x05U,
    0x2BU, 0x67U, 0x9AU, 0x76U, 0x2AU, 0xBEU, 0x04U, 0xC3U, 0xAAU, 0x44U, 0x13U, 0x26U, 0x49U, 0x86U, 0x06U, 0x99U,
    0x9CU, 0x42U, 0x50U, 0xF4U, 0x91U, 0xEFU, 0x98U, 0x7AU, 0x33U, 0x54U, 0x0BU, 0x43U, 0xEDU, 0xCFU, 0xACU, 0x62U,
    0xE4U, 0xB3U, 0x1CU, 0xA9U, 0xC9U, 0x08U, 0xE8U, 0x95U, 0x80U, 0xDFU, 0x94U, 0xFAU, 0x75U, 0x8FU, 0x3FU, 0xA6U,
    0x47U, 0x07U, 0xA7U, 0xFCU, 0xF3U, 0x73U, 0x17U, 0xBAU, 0x83U, 0x59U, 0x3CU, 0x19U, 0xE6U, 0x85U, 0x4FU, 0xA8U,
    0x68U, 0x6BU, 0x81U, 0xB2U, 0x71U, 0x64U, 0xDAU, 0x8BU, 0xF8U, 0xEBU, 0x0FU, 0x4BU, 0x70U, 0x56U, 0x9DU, 0x35U,
    0x1EU, 0x24U, 0x0EU, 0x5EU, 0x63U, 0x58U, 0xD1U, 0xA2U, 0x25U, 0x22U, 0x7CU, 0x3BU, 0x01U, 0x21U, 0x78U, 0x87U,
    0xD4U, 0x00U, 0x46U, 0x57U, 0x9FU, 0xD3U, 0x27U, 0x52U, 0x4CU, 0x36U, 0x02U, 0xE7U, 0xA0U, 0xC4U, 0xC8U, 0x9EU,
    0xEAU, 0xBFU, 0x8AU, 0xD2U, 0x40U, 0xC7U, 0x38U, 0xB5U, 0xA3U, 0xF7U, 0xF2U, 0xCEU, 0xF9U, 0x61U, 0x15U, 0xA1U,
    0xE0U, 0xAEU, 0x5DU, 0xA4U, 0x9BU, 0x34U, 0x1AU, 0x55U, 0xADU, 0x93U, 0x32U, 0x30U, 0xF5U, 0x8CU, 0xB1U, 0xE3U,
    0x1DU, 0xF6U, 0xE2U, 0x2EU, 0x82U, 0x66U, 0xCAU, 0x60U, 0xC0U, 0x29U, 0x23U, 0xABU, 0x0DU, 0x53U, 0x4EU, 0x6FU,
    0xD5U, 0xDBU, 0x37U, 0x45U, 0xDEU, 0xFDU, 0x8EU, 0x2FU, 0x03U, 0xFFU, 0x6AU, 0x72U, 0x6DU, 0x6CU, 0x5BU, 0x51U,
    0x8DU, 0x1BU, 0xAFU, 0x92U, 0xBBU, 0xDDU, 0xBCU, 0x7FU, 0x11U, 0xD9U, 0x5CU, 0x41U, 0x1FU, 0x10U, 0x5AU, 0xD8U,
    0x0AU, 0xC1U, 0x31U, 0x88U, 0xA5U, 0xCDU, 0x7BU, 0xBDU, 0x2DU, 0x74U, 0xD0U, 0x12U, 0xB8U, 0xE5U, 0xB4U, 0xB0U,
    0x89U, 0x69U, 0x97U, 0x4AU, 0x0CU, 0x96U, 0x77U, 0x7EU, 0x65U, 0xB9U, 0xF1U, 0x09U, 0xC5U, 0x6EU, 0xC6U, 0x84U,
    0x18U, 0xF0U, 0x7DU, 0xECU, 0x3AU, 0xDCU, 0x4DU, 0x20U, 0x79U, 0xEEU, 0x5FU, 0x3EU, 0xD7U, 0xCBU, 0x39U, 0x48U
};

static const uint32_t g_gateway_sm4_fk[4] = {
    0xA3B1BAC6U, 0x56AA3350U, 0x677D9197U, 0xB27022DCU
};

static const uint32_t g_gateway_sm4_ck[32] = {
    0x00070E15U, 0x1C232A31U, 0x383F464DU, 0x545B6269U,
    0x70777E85U, 0x8C939AA1U, 0xA8AFB6BDU, 0xC4CBD2D9U,
    0xE0E7EEF5U, 0xFC030A11U, 0x181F262DU, 0x343B4249U,
    0x50575E65U, 0x6C737A81U, 0x888F969DU, 0xA4ABB2B9U,
    0xC0C7CED5U, 0xDCE3EAF1U, 0xF8FF060DU, 0x141B2229U,
    0x30373E45U, 0x4C535A61U, 0x686F767DU, 0x848B9299U,
    0xA0A7AEB5U, 0xBCC3CAD1U, 0xD8DFE6EDU, 0xF4FB0209U,
    0x10171E25U, 0x2C333A41U, 0x484F565DU, 0x646B7279U
};

static uint8_t gateway_aes_xtime(uint8_t value)
{
    return (uint8_t)((value << 1) ^ (((value & 0x80U) != 0U) ? 0x1BU : 0x00U));
}

static void gateway_aes_add_round_key(uint8_t *state, const uint8_t *round_key)
{
    uint32_t i;

    for (i = 0U; i < 16U; ++i) {
        state[i] ^= round_key[i];
    }
}

static void gateway_aes_sub_bytes(uint8_t *state)
{
    uint32_t i;

    for (i = 0U; i < 16U; ++i) {
        state[i] = g_gateway_aes_sbox[state[i]];
    }
}

static void gateway_aes_shift_rows(uint8_t *state)
{
    uint8_t tmp;

    tmp = state[1];
    state[1] = state[5];
    state[5] = state[9];
    state[9] = state[13];
    state[13] = tmp;

    tmp = state[2];
    state[2] = state[10];
    state[10] = tmp;
    tmp = state[6];
    state[6] = state[14];
    state[14] = tmp;

    tmp = state[15];
    state[15] = state[11];
    state[11] = state[7];
    state[7] = state[3];
    state[3] = tmp;
}

static void gateway_aes_mix_columns(uint8_t *state)
{
    uint32_t column;

    for (column = 0U; column < 4U; ++column) {
        uint8_t *c = &state[column * 4U];
        uint8_t a0 = c[0];
        uint8_t a1 = c[1];
        uint8_t a2 = c[2];
        uint8_t a3 = c[3];
        uint8_t t = (uint8_t)(a0 ^ a1 ^ a2 ^ a3);
        uint8_t u = a0;

        c[0] ^= t ^ gateway_aes_xtime((uint8_t)(a0 ^ a1));
        c[1] ^= t ^ gateway_aes_xtime((uint8_t)(a1 ^ a2));
        c[2] ^= t ^ gateway_aes_xtime((uint8_t)(a2 ^ a3));
        c[3] ^= t ^ gateway_aes_xtime((uint8_t)(a3 ^ u));
    }
}

static void gateway_aes_expand_key(const uint8_t *key, uint8_t *round_keys)
{
    static const uint8_t rcon[10] = { 0x01U, 0x02U, 0x04U, 0x08U, 0x10U, 0x20U, 0x40U, 0x80U, 0x1BU, 0x36U };
    uint32_t generated = 16U;
    uint32_t rcon_index = 0U;
    uint8_t temp[4];

    memcpy(round_keys, key, 16U);
    while (generated < 176U) {
        temp[0] = round_keys[generated - 4U];
        temp[1] = round_keys[generated - 3U];
        temp[2] = round_keys[generated - 2U];
        temp[3] = round_keys[generated - 1U];

        if ((generated % 16U) == 0U) {
            uint8_t rotate = temp[0];
            temp[0] = g_gateway_aes_sbox[temp[1]] ^ rcon[rcon_index++];
            temp[1] = g_gateway_aes_sbox[temp[2]];
            temp[2] = g_gateway_aes_sbox[temp[3]];
            temp[3] = g_gateway_aes_sbox[rotate];
        }

        round_keys[generated] = round_keys[generated - 16U] ^ temp[0];
        generated++;
        round_keys[generated] = round_keys[generated - 16U] ^ temp[1];
        generated++;
        round_keys[generated] = round_keys[generated - 16U] ^ temp[2];
        generated++;
        round_keys[generated] = round_keys[generated - 16U] ^ temp[3];
        generated++;
    }
}

static void gateway_aes_encrypt_block_sw(const uint8_t *round_keys, const uint8_t *in_block, uint8_t *out_block)
{
    uint8_t state[16];
    uint32_t round;

    memcpy(state, in_block, 16U);
    gateway_aes_add_round_key(state, &round_keys[0]);

    for (round = 1U; round < 10U; ++round) {
        gateway_aes_sub_bytes(state);
        gateway_aes_shift_rows(state);
        gateway_aes_mix_columns(state);
        gateway_aes_add_round_key(state, &round_keys[round * 16U]);
    }

    gateway_aes_sub_bytes(state);
    gateway_aes_shift_rows(state);
    gateway_aes_add_round_key(state, &round_keys[160U]);
    memcpy(out_block, state, 16U);
}

static uint32_t gateway_rotate_left32(uint32_t value, uint32_t shift)
{
    return (value << shift) | (value >> (32U - shift));
}

static uint32_t gateway_sm4_tau(uint32_t value)
{
    return ((uint32_t)g_gateway_sm4_sbox[(value >> 24) & 0xFFU] << 24) |
           ((uint32_t)g_gateway_sm4_sbox[(value >> 16) & 0xFFU] << 16) |
           ((uint32_t)g_gateway_sm4_sbox[(value >> 8) & 0xFFU] << 8) |
           (uint32_t)g_gateway_sm4_sbox[value & 0xFFU];
}

static uint32_t gateway_sm4_l(uint32_t value)
{
    return value ^ gateway_rotate_left32(value, 2U) ^ gateway_rotate_left32(value, 10U) ^
           gateway_rotate_left32(value, 18U) ^ gateway_rotate_left32(value, 24U);
}

static uint32_t gateway_sm4_l_prime(uint32_t value)
{
    return value ^ gateway_rotate_left32(value, 13U) ^ gateway_rotate_left32(value, 23U);
}

static void gateway_sm4_expand_key(const uint8_t *key, uint32_t *round_keys)
{
    uint32_t k[36];
    uint32_t i;

    k[0] = gateway_load_be_word(&key[0]) ^ g_gateway_sm4_fk[0];
    k[1] = gateway_load_be_word(&key[4]) ^ g_gateway_sm4_fk[1];
    k[2] = gateway_load_be_word(&key[8]) ^ g_gateway_sm4_fk[2];
    k[3] = gateway_load_be_word(&key[12]) ^ g_gateway_sm4_fk[3];

    for (i = 0U; i < 32U; ++i) {
        uint32_t mix = k[i + 1U] ^ k[i + 2U] ^ k[i + 3U] ^ g_gateway_sm4_ck[i];
        k[i + 4U] = k[i] ^ gateway_sm4_l_prime(gateway_sm4_tau(mix));
        round_keys[i] = k[i + 4U];
    }
}

static void gateway_sm4_encrypt_block_sw(const uint32_t *round_keys, const uint8_t *in_block, uint8_t *out_block)
{
    uint32_t x[36];
    uint32_t i;

    x[0] = gateway_load_be_word(&in_block[0]);
    x[1] = gateway_load_be_word(&in_block[4]);
    x[2] = gateway_load_be_word(&in_block[8]);
    x[3] = gateway_load_be_word(&in_block[12]);

    for (i = 0U; i < 32U; ++i) {
        uint32_t mix = x[i + 1U] ^ x[i + 2U] ^ x[i + 3U] ^ round_keys[i];
        x[i + 4U] = x[i] ^ gateway_sm4_l(gateway_sm4_tau(mix));
    }

    gateway_store_be_word(&out_block[0], x[35]);
    gateway_store_be_word(&out_block[4], x[34]);
    gateway_store_be_word(&out_block[8], x[33]);
    gateway_store_be_word(&out_block[12], x[32]);
}

static int gateway_sw_encrypt_buffer(gateway_algo_t algo,
                                     const uint8_t *key,
                                     const uint8_t *input,
                                     uint8_t *output,
                                     uint16_t payload_len)
{
    uint16_t offset;

    if ((key == NULL) || (input == NULL) || (output == NULL) || ((payload_len % GATEWAY_BLOCK_BYTES) != 0U)) {
        return -1;
    }

    if (algo == GATEWAY_ALGO_SM4) {
        uint32_t round_keys[32];
        gateway_sm4_expand_key(key, round_keys);
        for (offset = 0U; offset < payload_len; offset = (uint16_t)(offset + GATEWAY_BLOCK_BYTES)) {
            gateway_sm4_encrypt_block_sw(round_keys, &input[offset], &output[offset]);
        }
    } else {
        uint8_t round_keys[176];
        gateway_aes_expand_key(key, round_keys);
        for (offset = 0U; offset < payload_len; offset = (uint16_t)(offset + GATEWAY_BLOCK_BYTES)) {
            gateway_aes_encrypt_block_sw(round_keys, &input[offset], &output[offset]);
        }
    }

    return 0;
}

static int gateway_wait_ready_sync(uint32_t limit, uint32_t *status_out)
{
    uint32_t poll;
    uint32_t status = 0U;

    for (poll = 0U; poll < limit; ++poll) {
        status = smoke_read32(REG_STATUS);
        if ((status & STATUS_SYS_READY) != 0U) {
            if (status_out != NULL) {
                *status_out = status;
            }
            return 0;
        }
    }

    if (status_out != NULL) {
        *status_out = status;
    }
    return -1;
}

static int gateway_wait_block_done_sync(uint32_t limit, uint32_t *status_out)
{
    uint32_t poll;
    uint32_t status = 0U;

    for (poll = 0U; poll < limit; ++poll) {
        status = smoke_read32(REG_STATUS);
        if (((status & STATUS_SYS_READY) != 0U) && ((status & STATUS_TX_EMPTY) == 0U)) {
            if (status_out != NULL) {
                *status_out = status;
            }
            return 0;
        }
    }

    if (status_out != NULL) {
        *status_out = status;
    }
    return -1;
}

static int gateway_drain_stale_output_sync(void)
{
    uint32_t drained_words = 0U;

    while (drained_words < GATEWAY_MAX_STALE_DRAIN_WORDS) {
        if ((smoke_read32(REG_STATUS) & STATUS_TX_EMPTY) != 0U) {
            return 0;
        }
        (void)smoke_read32(REG_DATA_OUT);
        drained_words++;
    }

    return 0;
}

static void gateway_load_key_hw_sync(gateway_algo_t algo, const uint8_t *effective_key)
{
    const uint32_t *key_offsets = (algo == GATEWAY_ALGO_SM4) ? g_gateway_sm4_key_offsets : g_gateway_aes_key_offsets;
    uint32_t i;

    for (i = 0U; i < 4U; ++i) {
        smoke_write32(key_offsets[i], gateway_load_be_word(&effective_key[i * 4U]));
    }
}

static int gateway_hw_encrypt_buffer_sync(gateway_algo_t algo,
                                          const uint8_t *effective_key,
                                          const uint8_t *input,
                                          uint8_t *output,
                                          uint16_t payload_len)
{
    uint16_t offset;
    uint32_t status = 0U;
    uint32_t word_index;

    if ((effective_key == NULL) || (input == NULL) || (output == NULL) || ((payload_len % GATEWAY_BLOCK_BYTES) != 0U)) {
        return -1;
    }

    if (gateway_wait_ready_sync(GATEWAY_WAIT_ENGINE_POLLS, &status) != 0) {
        g_stat_crypto_timeout++;
        return -1;
    }

    (void)gateway_drain_stale_output_sync();
    gateway_load_key_hw_sync(algo, effective_key);
    smoke_write32(REG_CTRL, gateway_ctrl_word(algo));

    for (offset = 0U; offset < payload_len; offset = (uint16_t)(offset + GATEWAY_BLOCK_BYTES)) {
        if (gateway_wait_ready_sync(GATEWAY_WAIT_ENGINE_POLLS, &status) != 0) {
            g_stat_crypto_timeout++;
            return -1;
        }

        for (word_index = 0U; word_index < 4U; ++word_index) {
            smoke_write32(REG_DATA_IN, gateway_load_be_word(&input[offset + (word_index * 4U)]));
        }

        if (gateway_wait_block_done_sync(GATEWAY_WAIT_BLOCK_POLLS, &status) != 0) {
            g_stat_crypto_timeout++;
            return -1;
        }

        for (word_index = 0U; word_index < 4U; ++word_index) {
            uint32_t poll_count = 0U;
            do {
                status = smoke_read32(REG_STATUS);
                if ((status & STATUS_TX_EMPTY) == 0U) {
                    break;
                }
                poll_count++;
            } while (poll_count < GATEWAY_WAIT_TX_WORD_POLLS);

            if ((status & STATUS_TX_EMPTY) != 0U) {
                g_stat_crypto_timeout++;
                return -1;
            }

            gateway_store_be_word(&output[offset + (word_index * 4U)], smoke_read32(REG_DATA_OUT));
        }
    }

    return 0;
}

static void gateway_fill_bench_input(gateway_algo_t algo, uint16_t payload_len, uint8_t *out)
{
    const uint8_t *block = (algo == GATEWAY_ALGO_SM4) ? g_gateway_bench_sm4_block : g_gateway_bench_aes_block;
    uint16_t offset;

    for (offset = 0U; offset < payload_len; offset = (uint16_t)(offset + GATEWAY_BLOCK_BYTES)) {
        memcpy(&out[offset], block, GATEWAY_BLOCK_BYTES);
    }
}

static uint32_t gateway_ticks_to_us(XTime delta_ticks)
{
    return (uint32_t)(((uint64_t)delta_ticks * 1000000ULL) / (uint64_t)COUNTS_PER_SECOND);
}

static int gateway_run_bench(gateway_session_t *session,
                             gateway_algo_t algo,
                             uint16_t repeats,
                             uint8_t *payload_out,
                             uint16_t *payload_len_out)
{
    uint8_t header[4];
    uint32_t record_index;
    const uint8_t *effective_key;
    uint16_t payload_len = 0U;

    if ((session == NULL) || (payload_out == NULL) || (payload_len_out == NULL)) {
        return -1;
    }

    if ((g_job_active != 0U) || (g_queue_count != 0U)) {
        return GATEWAY_CTRL_STATUS_BUSY;
    }

    if (repeats == 0U) {
        repeats = GATEWAY_DEFAULT_BENCH_REPEATS;
    }

    if (!gateway_session_allows_algo(session, algo)) {
        return GATEWAY_CTRL_STATUS_NOT_AUTHORIZED;
    }

    effective_key = gateway_session_key_for_algo(session, algo);
    if (effective_key == NULL) {
        return -1;
    }

    header[0] = (uint8_t)algo;
    header[1] = (uint8_t)GATEWAY_BENCH_RECORD_COUNT;
    gateway_store_be16(&header[2], repeats);
    memcpy(payload_out, header, sizeof(header));
    payload_len = GATEWAY_BENCH_HEADER_BYTES;

    for (record_index = 0U; record_index < GATEWAY_BENCH_RECORD_COUNT; ++record_index) {
        uint16_t current_len = g_gateway_bench_lengths[record_index];
        uint32_t repeat_index;
        XTime sw_start;
        XTime sw_end;
        XTime hw_start;
        XTime hw_end;
        uint32_t sw_us;
        uint32_t hw_us;
        uint8_t *record = &payload_out[payload_len];

        gateway_fill_bench_input(algo, current_len, g_bench_input);

        XTime_GetTime(&sw_start);
        for (repeat_index = 0U; repeat_index < repeats; ++repeat_index) {
            if (gateway_sw_encrypt_buffer(algo, effective_key, g_bench_input, g_bench_sw_output, current_len) != 0) {
                g_stat_crypto_fail++;
                return -1;
            }
        }
        XTime_GetTime(&sw_end);

        XTime_GetTime(&hw_start);
        for (repeat_index = 0U; repeat_index < repeats; ++repeat_index) {
            if (gateway_hw_encrypt_buffer_sync(algo, effective_key, g_bench_input, g_bench_hw_output, current_len) != 0) {
                g_stat_crypto_fail++;
                return -1;
            }
        }
        XTime_GetTime(&hw_end);

        if (memcmp(g_bench_sw_output, g_bench_hw_output, current_len) != 0) {
            g_stat_crypto_fail++;
            return -1;
        }

        sw_us = gateway_ticks_to_us(sw_end - sw_start);
        hw_us = gateway_ticks_to_us(hw_end - hw_start);

        gateway_store_be16(&record[0], current_len);
        gateway_store_be16(&record[2], 0U);
        gateway_store_be_word(&record[4], sw_us);
        gateway_store_be_word(&record[8], hw_us);
        payload_len = (uint16_t)(payload_len + GATEWAY_BENCH_RECORD_BYTES);
    }

    *payload_len_out = payload_len;
    return GATEWAY_CTRL_STATUS_OK;
}

static void log_job_timeout_and_drop(const char *phase_name, uint32_t status)
{
    g_stat_failures++;
    g_stat_crypto_timeout++;
    xil_printf("udp_crypto_gateway: timeout phase=%s algo=%s local_port=%u status=0x%08lx src=%u.%u.%u.%u:%u len=%u offset=%u pushed=%u pulled=%u sys_ready=%u tx_empty=%u failures=%lu\r\n",
               phase_name,
               gateway_algo_name(g_active_job.algo),
               (unsigned)gateway_reply_local_port(&g_active_job),
               (unsigned long)status,
               ip4_addr1(&g_active_job.remote_ip),
               ip4_addr2(&g_active_job.remote_ip),
               ip4_addr3(&g_active_job.remote_ip),
               ip4_addr4(&g_active_job.remote_ip),
               (unsigned)g_active_job.remote_port,
               (unsigned)g_active_job.payload_len,
               (unsigned)g_active_offset,
               (unsigned)g_active_words_pushed,
               (unsigned)g_active_words_pulled,
               (unsigned)((status & STATUS_SYS_READY) != 0U),
               (unsigned)((status & STATUS_TX_EMPTY) != 0U),
               (unsigned long)g_stat_failures);
    clear_active_job_state();
}

static int gateway_wait_or_drop(const char *phase_name, uint32_t status, uint32_t limit)
{
    g_job_wait_cycles++;
    if (g_job_wait_cycles < limit) {
        return 0;
    }

    log_job_timeout_and_drop(phase_name, status);
    return -1;
}

static void gateway_drain_stale_output(void)
{
    uint32_t drained_words = 0U;
    uint32_t status;
    int verbose = gateway_log_block_details(&g_active_job);

    while (drained_words < GATEWAY_MAX_STALE_DRAIN_WORDS) {
        status = smoke_read32(REG_STATUS);
        if ((status & STATUS_TX_EMPTY) != 0U) {
            break;
        }

        {
            uint32_t stale_word = smoke_read32(REG_DATA_OUT);
            if (verbose) {
                xil_printf("udp_crypto_gateway: stale_data_out[%lu]=0x%08lx status=0x%08lx\r\n",
                           (unsigned long)drained_words,
                           (unsigned long)stale_word,
                           (unsigned long)status);
            }
        }
        drained_words++;
    }

    xil_printf("udp_crypto_gateway: stale_drain words=%lu final_status=0x%08lx\r\n",
               (unsigned long)drained_words,
               (unsigned long)smoke_read32(REG_STATUS));
}

static void gateway_push_single_block(const uint8_t *in_block, uint16_t block_offset)
{
    uint32_t i;
    int verbose = gateway_log_block_details(&g_active_job);
    uint32_t base_word_index = (uint32_t)block_offset / 4U;

    for (i = 0U; i < 4U; ++i) {
        uint32_t din = gateway_load_be_word(&in_block[i * 4U]);
        if (verbose) {
            xil_printf("udp_crypto_gateway: data_in[%lu]=0x%08lx\r\n",
                       (unsigned long)(base_word_index + i),
                       (unsigned long)din);
        }
        smoke_write32(REG_DATA_IN, din);
    }
}

static int gateway_pull_single_block_bounded(uint8_t *out_block, uint16_t block_offset)
{
    uint32_t i;
    uint32_t poll_count;
    uint32_t status = 0U;
    uint32_t base_word_index = (uint32_t)block_offset / 4U;
    int verbose = gateway_log_block_details(&g_active_job);

    for (i = 0U; i < 4U; ++i) {
        poll_count = 0U;
        do {
            status = smoke_read32(REG_STATUS);
            if ((status & STATUS_TX_EMPTY) == 0U) {
                break;
            }
            poll_count++;
        } while (poll_count < GATEWAY_WAIT_TX_WORD_POLLS);

        if ((status & STATUS_TX_EMPTY) != 0U) {
            log_job_timeout_and_drop("tx_word_ready", status);
            return -1;
        }

        {
            uint32_t dout = smoke_read32(REG_DATA_OUT);
            gateway_store_be_word(&out_block[i * 4U], dout);
            if (verbose) {
                xil_printf("udp_crypto_gateway: raw_data_out[%lu]=0x%08lx status=0x%08lx\r\n",
                           (unsigned long)(base_word_index + i),
                           (unsigned long)dout,
                           (unsigned long)status);
            }
        }
        g_active_words_pulled = (uint8_t)(base_word_index + i + 1U);
    }

    return 0;
}
#endif

static uint32_t smoke_write_once_and_readback(const char *phase_name, uint32_t offset, uint32_t value)
{
    uint32_t before;
    uint32_t after;

    before = smoke_read32(offset);
    xil_printf("WRITE phase=%s offset=0x%08lx value=0x%08lx before=0x%08lx\r\n",
               phase_name,
               (unsigned long)offset,
               (unsigned long)value,
               (unsigned long)before);
    smoke_uart_drain();
    xil_printf("SMOKE_MARK pre_write phase=%s %s:%d offset=0x%08lx value=0x%08lx\r\n",
               phase_name,
               __FILE__,
               __LINE__,
               (unsigned long)offset,
               (unsigned long)value);
    smoke_uart_drain();
    smoke_write32(offset, value);
    xil_printf("SMOKE_MARK post_write phase=%s %s:%d offset=0x%08lx value=0x%08lx\r\n",
               phase_name,
               __FILE__,
               __LINE__,
               (unsigned long)offset,
               (unsigned long)value);
    smoke_uart_drain();
    after = smoke_read32(offset);
    xil_printf("READBACK phase=%s offset=0x%08lx value=0x%08lx\r\n",
               phase_name,
               (unsigned long)offset,
               (unsigned long)after);
    return after;
}

static int smoke_wait_for_status(const char *phase_name,
                                 uint32_t mask,
                                 uint32_t expected,
                                 uint32_t timeout_cycles,
                                 uint32_t pushed_words,
                                 uint32_t pulled_words,
                                 uint32_t *final_status)
{
    uint32_t last_status = 0U;

    while (timeout_cycles-- > 0U) {
        last_status = smoke_read32(REG_STATUS);
        if ((last_status & mask) == expected) {
            if (final_status != NULL) {
                *final_status = last_status;
            }
            return 0;
        }
    }

    if (final_status != NULL) {
        *final_status = last_status;
    }

    xil_printf("TEST fail: timeout phase=%s status=0x%08lx pushed=%lu pulled=%lu sys_ready=%lu tx_empty=%lu\r\n",
               phase_name,
               (unsigned long)last_status,
               (unsigned long)pushed_words,
               (unsigned long)pulled_words,
               (unsigned long)(last_status & STATUS_SYS_READY),
               (unsigned long)((last_status & STATUS_TX_EMPTY) != 0U));
    return -1;
}

static void smoke_drain_stale_output(void)
{
    uint32_t drained_words = 0U;
    uint32_t status = 0U;

    while (drained_words < SMOKE_MAX_DRAIN_WORDS) {
        status = smoke_read32(REG_STATUS);
        if ((status & STATUS_TX_EMPTY) != 0U) {
            break;
        }

        xil_printf("STALE_DATA_OUT[%lu] = 0x%08lx status=0x%08lx\r\n",
                   (unsigned long)drained_words,
                   (unsigned long)smoke_read32(REG_DATA_OUT),
                   (unsigned long)status);
        drained_words++;
    }

    xil_printf("drained_words=%lu final_status=0x%08lx\r\n",
               (unsigned long)drained_words,
               (unsigned long)smoke_read32(REG_STATUS));
}

static int smoke_aes_block_encrypt(void)
{
    static const uint32_t key_words[4] = {
        0x2B7E1516U, 0x28AED2A6U, 0xABF71588U, 0x09CF4F3CU
    };
    static const uint32_t key_offsets[4] = {
        REG_KEY_0 + 0x0CU, REG_KEY_0 + 0x08U, REG_KEY_0 + 0x04U, REG_KEY_0 + 0x00U
    };
    static const uint32_t plain_words[4] = {
        0x3243F6A8U, 0x885A308DU, 0x313198A2U, 0xE0370734U
    };
    static const uint32_t expected_words[4] = {
        0x3925841DU, 0x02DC09FBU, 0xDC118597U, 0x196A0B32U
    };
    uint32_t actual_words[4];
    uint32_t status = 0U;
    uint32_t i;
    int pass = 1;

    xil_printf("TEST begin: aes_block_smoke_enc\r\n");
    smoke_print_word_vector("AES_KEY_WORD", key_words, 4U);
    smoke_print_word_vector("AES_PLAIN_WORD", plain_words, 4U);
    smoke_print_word_vector("AES_EXPECT_WORD", expected_words, 4U);

    smoke_drain_stale_output();

    for (i = 0U; i < 4U; ++i) {
        xil_printf("AES_LOAD_KEY[%lu] offset=0x%08lx value=0x%08lx\r\n",
                   (unsigned long)i,
                   (unsigned long)key_offsets[i],
                   (unsigned long)key_words[i]);
        smoke_write32(key_offsets[i], key_words[i]);
    }

    xil_printf("AES_CTRL value=0x%08lx\r\n", (unsigned long)SMOKE_AES_CTRL_WORD);
    smoke_uart_drain();
    xil_printf("SMOKE_MARK pre_write phase=aes_ctrl %s:%d offset=0x%08lx value=0x%08lx\r\n",
               __FILE__,
               __LINE__,
               (unsigned long)REG_CTRL,
               (unsigned long)SMOKE_AES_CTRL_WORD);
    smoke_uart_drain();
    smoke_write32(REG_CTRL, SMOKE_AES_CTRL_WORD);
    xil_printf("SMOKE_MARK post_write phase=aes_ctrl %s:%d offset=0x%08lx value=0x%08lx\r\n",
               __FILE__,
               __LINE__,
               (unsigned long)REG_CTRL,
               (unsigned long)SMOKE_AES_CTRL_WORD);
    smoke_uart_drain();

    if (smoke_wait_for_status("ctrl_ready",
                              STATUS_SYS_READY,
                              STATUS_SYS_READY,
                              SMOKE_STATUS_TIMEOUT_CTRL_READY,
                              0U,
                              0U,
                              &status) != 0) {
        return -1;
    }
    smoke_print_status_line("STATUS after ctrl_ready = ", status);

    for (i = 0U; i < 4U; ++i) {
        xil_printf("AES_DATA_IN[%lu] = 0x%08lx\r\n",
                   (unsigned long)i,
                   (unsigned long)plain_words[i]);
        smoke_write32(REG_DATA_IN, plain_words[i]);
    }

    if (smoke_wait_for_status("block_done",
                              STATUS_SYS_READY,
                              STATUS_SYS_READY,
                              SMOKE_STATUS_TIMEOUT_BLOCK_DONE,
                              4U,
                              0U,
                              &status) != 0) {
        return -1;
    }
    smoke_print_status_line("STATUS after block_done = ", status);

    for (i = 0U; i < 4U; ++i) {
        if (smoke_wait_for_status("tx_word_ready",
                                  STATUS_TX_EMPTY,
                                  0U,
                                  SMOKE_STATUS_TIMEOUT_TX_WORD,
                                  4U,
                                  i,
                                  &status) != 0) {
            return -1;
        }

        actual_words[i] = smoke_read32(REG_DATA_OUT);
        xil_printf("RAW_DATA_OUT[%lu] = 0x%08lx status=0x%08lx\r\n",
                   (unsigned long)i,
                   (unsigned long)actual_words[i],
                   (unsigned long)status);
        if (actual_words[i] != expected_words[i]) {
            pass = 0;
        }
    }

    if (pass == 0) {
        smoke_print_word_vector("AES_ACTUAL_WORD", actual_words, 4U);
        smoke_print_word_vector("AES_EXPECT_WORD", expected_words, 4U);
        xil_printf("TEST done: aes_block_smoke_enc FAIL\r\n");
        return -1;
    }

    xil_printf("TEST done: aes_block_smoke_enc PASS\r\n");
    return 0;
}

static void smoke_write_flip_readback(const char *case_name, uint32_t offset, uint32_t value0, uint32_t value1)
{
    uint32_t before;
    uint32_t readback0;
    uint32_t readback1;

    before = smoke_read32(offset);
    xil_printf("TEST begin: %s offset=0x%08lx value0=0x%08lx value1=0x%08lx before=0x%08lx\r\n",
               case_name,
               (unsigned long)offset,
               (unsigned long)value0,
               (unsigned long)value1,
               (unsigned long)before);
    readback0 = smoke_write_once_and_readback("flip0", offset, value0);
    readback1 = smoke_write_once_and_readback("flip1", offset, value1);
    xil_printf("TEST done: %s offset=0x%08lx readback0=0x%08lx readback1=0x%08lx\r\n",
               case_name,
               (unsigned long)offset,
               (unsigned long)readback0,
               (unsigned long)readback1);
}

static void smoke_write_ctrl_safe(void)
{
    uint32_t before_status;
    uint32_t after_status;

    before_status = smoke_read32(REG_STATUS);
    xil_printf("TEST begin: write_ctrl_safe offset=0x%08lx value=0x00000000 status_before=0x%08lx\r\n",
               (unsigned long)REG_CTRL,
               (unsigned long)before_status);
    smoke_uart_drain();
    xil_printf("SMOKE_MARK pre_write phase=ctrl_safe %s:%d offset=0x%08lx value=0x00000000\r\n",
               __FILE__,
               __LINE__,
               (unsigned long)REG_CTRL);
    smoke_uart_drain();
    smoke_write32(REG_CTRL, 0x00000000U);
    xil_printf("SMOKE_MARK post_write phase=ctrl_safe %s:%d offset=0x%08lx value=0x00000000\r\n",
               __FILE__,
               __LINE__,
               (unsigned long)REG_CTRL);
    smoke_uart_drain();
    after_status = smoke_read32(REG_STATUS);
    xil_printf("STATUS after ctrl_safe = 0x%08lx\r\n", (unsigned long)after_status);
    xil_printf("TEST done: write_ctrl_safe status_before=0x%08lx status_after=0x%08lx\r\n",
               (unsigned long)before_status,
               (unsigned long)after_status);
}

void udp_crypto_gateway_run_direct_smoke(unsigned case_id)
{
    uint32_t initial_status;

    smoke_prepare_mmio_region();
    xil_printf("AX7020 DIRECT CRYPTO WRITE SMOKE\r\n");
    xil_printf("TEST_CASE=%s\r\n", direct_smoke_case_name(case_id));
    smoke_print_status_line("CRYPTO_BASE_ADDR = ", CRYPTO_BASE_ADDR);
    xil_printf("MMIO_ATTR = STRONG_ORDERED\r\n");

    initial_status = smoke_read32(REG_STATUS);
    smoke_print_status_line("REG_STATUS initial = ", initial_status);

    switch (case_id) {
    case 1U: {
        uint32_t status = smoke_read32(REG_STATUS);
        xil_printf("TEST begin: read_only status\r\n");
        smoke_print_status_line("READ REG_STATUS = ", status);
        xil_printf("TEST done: read_only status\r\n");
        break;
    }
    case 2U:
        smoke_write_flip_readback("write_key_10_flip", REG_KEY_0 + 0x00U, SMOKE_KEY_PATTERN_10, SMOKE_KEY_PATTERN_10_FLIP);
        break;
    case 3U:
        smoke_write_flip_readback("write_key_14_flip", REG_KEY_0 + 0x04U, SMOKE_KEY_PATTERN_14, SMOKE_KEY_PATTERN_14_FLIP);
        break;
    case 4U:
        smoke_write_flip_readback("write_key_18_flip", REG_KEY_0 + 0x08U, SMOKE_KEY_PATTERN_18, SMOKE_KEY_PATTERN_18_FLIP);
        break;
    case 5U:
        smoke_write_flip_readback("write_key_1c_flip", REG_KEY_0 + 0x0CU, SMOKE_KEY_PATTERN_1C, SMOKE_KEY_PATTERN_1C_FLIP);
        break;
    case 6U:
        smoke_write_ctrl_safe();
        break;
    case 7U:
        (void)smoke_aes_block_encrypt();
        break;
    default:
        xil_printf("TEST begin: invalid_test_case\r\n");
        xil_printf("TEST done: invalid_test_case\r\n");
        break;
    }
}

#if !UDP_GATEWAY_SMOKE_ONLY_BUILD
static int queue_push(gateway_algo_t algo,
                      struct udp_pcb *reply_pcb,
                      const ip_addr_t *remote_ip,
                      uint16_t remote_port,
                      uint32_t session_id,
                      const uint8_t *effective_key,
                      const uint8_t *payload,
                      uint16_t payload_len)
{
    gateway_request_t *slot;

    if (g_queue_count >= GATEWAY_QUEUE_DEPTH) {
        return -1;
    }

    slot = &g_queue[g_queue_tail];
    memset(slot, 0, sizeof(*slot));
    slot->algo = algo;
    slot->reply_pcb = reply_pcb;
    ip_addr_copy(slot->remote_ip, *remote_ip);
    slot->remote_port = remote_port;
    slot->payload_len = payload_len;
    slot->session_id = session_id;
    memcpy(slot->effective_key, effective_key, sizeof(slot->effective_key));
    memcpy(slot->payload, payload, payload_len);

    g_queue_tail = (uint8_t)((g_queue_tail + 1U) % GATEWAY_QUEUE_DEPTH);
    g_queue_count++;
    return 0;
}

static int queue_pop(gateway_request_t *out_req)
{
    if (g_queue_count == 0U) {
        return -1;
    }

    *out_req = g_queue[g_queue_head];
    g_queue_head = (uint8_t)((g_queue_head + 1U) % GATEWAY_QUEUE_DEPTH);
    g_queue_count--;
    return 0;
}

static void udp_control_callback(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
    uint8_t packet[GATEWAY_CONTROL_HEADER_BYTES + GATEWAY_MAX_CONTROL_PAYLOAD_BYTES];
    uint8_t response_payload[GATEWAY_MAX_CONTROL_PAYLOAD_BYTES];
    uint16_t total_len;
    uint16_t payload_len;
    uint16_t response_payload_len = 0U;
    uint16_t status_code = GATEWAY_CTRL_STATUS_OK;
    uint16_t copied;
    uint32_t magic;
    uint32_t session_id;
    uint32_t seq_id;
    uint32_t auth_tag;
    uint32_t binding_id = gateway_get_device_binding_id();
    gateway_session_t *session = NULL;
    uint8_t version;
    uint8_t msg_type;
    uint8_t flags;

    (void)arg;
    if (p == NULL) {
        return;
    }

    total_len = (uint16_t)p->tot_len;
    if ((total_len < GATEWAY_CONTROL_HEADER_BYTES) ||
        (total_len > (GATEWAY_CONTROL_HEADER_BYTES + GATEWAY_MAX_CONTROL_PAYLOAD_BYTES))) {
        g_stat_drops_invalid++;
        pbuf_free(p);
        return;
    }

    copied = pbuf_copy_partial(p, packet, total_len, 0U);
    pbuf_free(p);
    if (copied != total_len) {
        g_stat_drops_invalid++;
        return;
    }

    magic = gateway_load_be_word(&packet[0]);
    version = packet[4];
    msg_type = packet[5];
    flags = packet[6];
    session_id = gateway_load_be_word(&packet[8]);
    seq_id = gateway_load_be_word(&packet[12]);
    payload_len = gateway_load_be16(&packet[16]);
    auth_tag = gateway_load_be_word(&packet[20]);

    if (magic != GATEWAY_CTRL_MAGIC) {
        status_code = GATEWAY_CTRL_STATUS_BAD_MAGIC;
        gateway_send_control_response(pcb, addr, port, msg_type, flags, session_id, seq_id, status_code, NULL, 0U, binding_id);
        return;
    }

    if (version != GATEWAY_CTRL_VERSION) {
        status_code = GATEWAY_CTRL_STATUS_BAD_VERSION;
        gateway_send_control_response(pcb, addr, port, msg_type, flags, session_id, seq_id, status_code, NULL, 0U, binding_id);
        return;
    }

    if ((payload_len > GATEWAY_MAX_CONTROL_PAYLOAD_BYTES) ||
        (total_len != (uint16_t)(GATEWAY_CONTROL_HEADER_BYTES + payload_len))) {
        status_code = GATEWAY_CTRL_STATUS_BAD_LENGTH;
        gateway_send_control_response(pcb, addr, port, msg_type, flags, session_id, seq_id, status_code, NULL, 0U, binding_id);
        return;
    }

    if (msg_type == GATEWAY_CTRL_MSG_HELLO) {
        session = gateway_alloc_session(addr);
        if (session == NULL) {
            gateway_send_control_response(pcb, addr, port, msg_type, flags, 0U, 0U, GATEWAY_CTRL_STATUS_INTERNAL, NULL, 0U, binding_id);
            return;
        }

        binding_id = session->binding_id;
        gateway_store_be_word(response_payload, binding_id);
        response_payload_len = 4U;
        g_stat_rx_ctrl_ok++;
        gateway_send_control_response(pcb,
                                      addr,
                                      port,
                                      msg_type,
                                      flags,
                                      session->session_id,
                                      0U,
                                      GATEWAY_CTRL_STATUS_OK,
                                      response_payload,
                                      response_payload_len,
                                      binding_id);
        return;
    }

    session = gateway_find_session_by_id(addr, session_id);
    if (session == NULL) {
        gateway_send_control_response(pcb, addr, port, msg_type, flags, session_id, seq_id, GATEWAY_CTRL_STATUS_NO_SESSION, NULL, 0U, binding_id);
        return;
    }

    binding_id = session->binding_id;
    if ((session->locked != 0U) &&
        (msg_type != GATEWAY_CTRL_MSG_STATUS) &&
        (msg_type != GATEWAY_CTRL_MSG_UNLOCK)) {
        gateway_send_control_response(pcb, addr, port, msg_type, flags, session_id, seq_id, GATEWAY_CTRL_STATUS_LOCKED, NULL, 0U, binding_id);
        return;
    }

    if (gateway_control_auth_ok(session,
                                msg_type,
                                session_id,
                                seq_id,
                                flags,
                                GATEWAY_CTRL_STATUS_OK,
                                &packet[GATEWAY_CONTROL_HEADER_BYTES],
                                payload_len,
                                auth_tag) != 0) {
        g_stat_bind_fail++;
        session->auth_failures++;
        if (session->auth_failures >= GATEWAY_AUTH_FAILURE_THRESHOLD) {
            gateway_lock_session(session);
        }
        gateway_send_control_response(pcb, addr, port, msg_type, flags, session_id, seq_id, GATEWAY_CTRL_STATUS_AUTH_FAIL, NULL, 0U, binding_id);
        return;
    }

    if (gateway_check_and_update_seq(session, seq_id) != 0) {
        g_stat_drop_replay++;
        session->replay_failures++;
        if (session->replay_failures >= GATEWAY_REPLAY_FAILURE_THRESHOLD) {
            gateway_lock_session(session);
        }
        gateway_send_control_response(pcb, addr, port, msg_type, flags, session_id, seq_id, GATEWAY_CTRL_STATUS_REPLAY, NULL, 0U, binding_id);
        return;
    }

    session->auth_failures = 0U;
    session->replay_failures = 0U;

    switch (msg_type) {
    case GATEWAY_CTRL_MSG_SET_KEY:
        if (payload_len != 16U) {
            status_code = GATEWAY_CTRL_STATUS_BAD_LENGTH;
            break;
        }
        if ((flags & (GATEWAY_ALGO_FLAG_AES | GATEWAY_ALGO_FLAG_SM4)) == 0U) {
            status_code = GATEWAY_CTRL_STATUS_BAD_LENGTH;
            break;
        }
        if ((flags & GATEWAY_ALGO_FLAG_AES) != 0U) {
            gateway_derive_effective_key(&packet[GATEWAY_CONTROL_HEADER_BYTES],
                                         session->binding_id,
                                         GATEWAY_ALGO_AES,
                                         session->effective_key_aes);
        }
        if ((flags & GATEWAY_ALGO_FLAG_SM4) != 0U) {
            gateway_derive_effective_key(&packet[GATEWAY_CONTROL_HEADER_BYTES],
                                         session->binding_id,
                                         GATEWAY_ALGO_SM4,
                                         session->effective_key_sm4);
        }
        session->authorized_algos |= (uint8_t)(flags & (GATEWAY_ALGO_FLAG_AES | GATEWAY_ALGO_FLAG_SM4));
        break;

    case GATEWAY_CTRL_MSG_LOCK:
        gateway_lock_session(session);
        break;

    case GATEWAY_CTRL_MSG_UNLOCK:
        gateway_unlock_session(session);
        break;

    case GATEWAY_CTRL_MSG_STATUS:
        gateway_pack_status_payload(response_payload, session);
        response_payload_len = GATEWAY_STATUS_PAYLOAD_BYTES;
        break;

    case GATEWAY_CTRL_MSG_BENCH: {
        gateway_algo_t algo;
        uint16_t repeats;

        if (payload_len != 2U) {
            status_code = GATEWAY_CTRL_STATUS_BAD_LENGTH;
            break;
        }
        if ((flags & GATEWAY_ALGO_FLAG_SM4) != 0U) {
            algo = GATEWAY_ALGO_SM4;
        } else if ((flags & GATEWAY_ALGO_FLAG_AES) != 0U) {
            algo = GATEWAY_ALGO_AES;
        } else {
            status_code = GATEWAY_CTRL_STATUS_BAD_LENGTH;
            break;
        }
        repeats = gateway_load_be16(&packet[GATEWAY_CONTROL_HEADER_BYTES]);
        status_code = (uint16_t)gateway_run_bench(session, algo, repeats, response_payload, &response_payload_len);
        break;
    }

    default:
        status_code = GATEWAY_CTRL_STATUS_UNKNOWN_MSG;
        break;
    }

    if (status_code == GATEWAY_CTRL_STATUS_OK) {
        g_stat_rx_ctrl_ok++;
    }

    gateway_send_control_response(pcb,
                                  addr,
                                  port,
                                  msg_type,
                                  flags,
                                  session_id,
                                  seq_id,
                                  status_code,
                                  response_payload_len != 0U ? response_payload : NULL,
                                  response_payload_len,
                                  binding_id);
}

static void udp_rx_callback(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
    const gateway_listener_context_t *listener = (const gateway_listener_context_t *)arg;
    gateway_session_t *session = NULL;
    const uint8_t *effective_key = NULL;
    uint16_t payload_len;
    uint8_t local_payload[GATEWAY_MAX_PAYLOAD_BYTES];
    u16_t copied;

    if (p == NULL) {
        return;
    }

    payload_len = (uint16_t)p->tot_len;
    xil_printf("udp_crypto_gateway: rx_callback entry algo=%s local_port=%u len=%u src_port=%u\r\n",
               gateway_algo_name((listener != NULL) ? listener->algo : GATEWAY_ALGO_AES),
               (unsigned)((pcb != NULL) ? pcb->local_port : 0U),
               (unsigned)payload_len,
               (unsigned)port);
    if ((payload_len == 0U) ||
        (payload_len > GATEWAY_MAX_PAYLOAD_BYTES) ||
        ((payload_len & (GATEWAY_BLOCK_BYTES - 1U)) != 0U)) {
        g_stat_drops_invalid++;
        xil_printf("udp_crypto_gateway: drop invalid algo=%s local_port=%u len=%u\r\n",
                   gateway_algo_name((listener != NULL) ? listener->algo : GATEWAY_ALGO_AES),
                   (unsigned)((pcb != NULL) ? pcb->local_port : 0U),
                   (unsigned)payload_len);
        pbuf_free(p);
        return;
    }

    session = gateway_find_session_by_ip(addr);
    if (!gateway_session_allows_algo(session, (listener != NULL) ? listener->algo : GATEWAY_ALGO_AES)) {
        g_stat_drop_unauthorized++;
        xil_printf("udp_crypto_gateway: drop unauthorized algo=%s local_port=%u len=%u src=%u.%u.%u.%u:%u\r\n",
                   gateway_algo_name((listener != NULL) ? listener->algo : GATEWAY_ALGO_AES),
                   (unsigned)((pcb != NULL) ? pcb->local_port : 0U),
                   (unsigned)payload_len,
                   ip4_addr1(addr),
                   ip4_addr2(addr),
                   ip4_addr3(addr),
                   ip4_addr4(addr),
                   (unsigned)port);
        pbuf_free(p);
        return;
    }
    effective_key = gateway_session_key_for_algo(session, (listener != NULL) ? listener->algo : GATEWAY_ALGO_AES);
    if (effective_key == NULL) {
        g_stat_drop_unauthorized++;
        pbuf_free(p);
        return;
    }

    copied = pbuf_copy_partial(p, local_payload, payload_len, 0U);
    pbuf_free(p);
    if (copied != payload_len) {
        g_stat_drops_invalid++;
        xil_printf("udp_crypto_gateway: drop partial_copy algo=%s local_port=%u copied=%u len=%u\r\n",
                   gateway_algo_name((listener != NULL) ? listener->algo : GATEWAY_ALGO_AES),
                   (unsigned)((pcb != NULL) ? pcb->local_port : 0U),
                   (unsigned)copied,
                   (unsigned)payload_len);
        return;
    }

    if (queue_push((listener != NULL) ? listener->algo : GATEWAY_ALGO_AES,
                   pcb,
                   addr,
                   port,
                   (session != NULL) ? session->session_id : 0U,
                   effective_key,
                   local_payload,
                   payload_len) != 0) {
        g_stat_drops_busy++;
        xil_printf("udp_crypto_gateway: queue full algo=%s local_port=%u len=%u\r\n",
                   gateway_algo_name((listener != NULL) ? listener->algo : GATEWAY_ALGO_AES),
                   (unsigned)((pcb != NULL) ? pcb->local_port : 0U),
                   (unsigned)payload_len);
    } else {
        g_stat_rx_data_ok++;
        xil_printf("udp_crypto_gateway: queued algo=%s local_port=%u len=%u from port=%u\r\n",
                   gateway_algo_name((listener != NULL) ? listener->algo : GATEWAY_ALGO_AES),
                   (unsigned)((pcb != NULL) ? pcb->local_port : 0U),
                   (unsigned)payload_len,
                   (unsigned)port);
    }
}

static int send_active_response(void)
{
    struct pbuf *resp;
    err_t err;

    xil_printf("udp_crypto_gateway: send_active_response algo=%s local_port=%u len=%u dst=%u.%u.%u.%u:%u\r\n",
               gateway_algo_name(g_active_job.algo),
               (unsigned)gateway_reply_local_port(&g_active_job),
               (unsigned)g_active_job.payload_len,
               ip4_addr1(&g_active_job.remote_ip),
               ip4_addr2(&g_active_job.remote_ip),
               ip4_addr3(&g_active_job.remote_ip),
               ip4_addr4(&g_active_job.remote_ip),
               (unsigned)g_active_job.remote_port);

    resp = pbuf_alloc(PBUF_TRANSPORT, g_active_job.payload_len, PBUF_RAM);
    if (resp == NULL) {
        xil_printf("udp_crypto_gateway: pbuf_alloc failed\r\n");
        return -1;
    }

    err = pbuf_take(resp, g_active_job.ciphertext, g_active_job.payload_len);
    if ((err == ERR_OK) && (g_active_job.reply_pcb != NULL)) {
        err = udp_sendto(g_active_job.reply_pcb, resp, &g_active_job.remote_ip, g_active_job.remote_port);
    }
    pbuf_free(resp);

    if (err != ERR_OK) {
        xil_printf("udp_crypto_gateway: udp_sendto failed algo=%s local_port=%u err=%d\r\n",
                   gateway_algo_name(g_active_job.algo),
                   (unsigned)gateway_reply_local_port(&g_active_job),
                   (int)err);
        return -1;
    }

    g_stat_completed++;
    g_stat_tx_ok++;
    xil_printf("udp_crypto_gateway: response sent algo=%s local_port=%u len=%u total=%lu\r\n",
               gateway_algo_name(g_active_job.algo),
               (unsigned)gateway_reply_local_port(&g_active_job),
               (unsigned)g_active_job.payload_len,
               (unsigned long)g_stat_completed);
    return 0;
}

static void start_next_job_if_available(void)
{
    if (g_job_active) {
        return;
    }

    if (queue_pop(&g_active_job) != 0) {
        return;
    }

    g_active_offset = 0U;
    g_active_job.offset = 0U;
    g_active_job.key_loaded = 0U;
    g_active_job.ctrl_armed = 0U;
    g_job_active = 1U;
    g_job_state = JOB_WAIT_ENGINE_READY;
    g_active_words_pushed = 0U;
    g_active_words_pulled = 0U;
    g_stat_jobs_started++;
    xil_printf("udp_crypto_gateway: job_start seq=%lu algo=%s local_port=%u len=%u src=%u.%u.%u.%u:%u state=%s qdepth=%u\r\n",
               (unsigned long)g_stat_jobs_started,
               gateway_algo_name(g_active_job.algo),
               (unsigned)gateway_reply_local_port(&g_active_job),
               (unsigned)g_active_job.payload_len,
               ip4_addr1(&g_active_job.remote_ip),
               ip4_addr2(&g_active_job.remote_ip),
               ip4_addr3(&g_active_job.remote_ip),
               ip4_addr4(&g_active_job.remote_ip),
               (unsigned)g_active_job.remote_port,
               job_state_name(g_job_state),
               (unsigned)g_queue_count);
    reset_job_wait_debug();
}

static void service_active_job(void)
{
    uint32_t status;

    if (!g_job_active) {
        return;
    }

    status = HW_READ(REG_STATUS);
    switch (g_job_state) {
    case JOB_WAIT_ENGINE_READY:
        if ((status & STATUS_SYS_READY) == 0U) {
            if (gateway_wait_or_drop("engine_ready", status, GATEWAY_WAIT_ENGINE_POLLS) != 0) {
                return;
            }
            return;
        }
        if (gateway_log_block_details(&g_active_job) || (g_active_offset == 0U)) {
            xil_printf("udp_crypto_gateway: state=%s ready status=0x%08lx offset=%u/%u\r\n",
                       job_state_name(g_job_state),
                       (unsigned long)status,
                       (unsigned)g_active_offset,
                       (unsigned)g_active_job.payload_len);
        }
        reset_job_wait_debug();
        if (g_active_job.key_loaded == 0U) {
            gateway_drain_stale_output();
            g_job_state = JOB_LOAD_KEY;
        } else if (g_active_job.ctrl_armed == 0U) {
            g_job_state = JOB_CONFIG_CTRL;
        } else {
            g_job_state = JOB_WAIT_INPUT_ACCEPT;
        }
        reset_job_wait_debug();
        return;

    case JOB_LOAD_KEY:
        gateway_load_key_to_hw(&g_active_job);
        g_active_job.key_loaded = 1U;
        g_job_state = JOB_CONFIG_CTRL;
        reset_job_wait_debug();
        return;

    case JOB_CONFIG_CTRL: {
        uint32_t ctrl_word = gateway_ctrl_word(g_active_job.algo);
        xil_printf("udp_crypto_gateway: ctrl_write algo=%s begin value=0x%08lx\r\n",
                   gateway_algo_name(g_active_job.algo),
                   (unsigned long)ctrl_word);
        smoke_write32(REG_CTRL, ctrl_word);
        xil_printf("udp_crypto_gateway: ctrl_written algo=%s status_after=0x%08lx\r\n",
                   gateway_algo_name(g_active_job.algo),
                   (unsigned long)smoke_read32(REG_STATUS));
        g_active_job.ctrl_armed = 1U;
        g_job_state = JOB_WAIT_INPUT_ACCEPT;
        reset_job_wait_debug();
        return;
    }

    case JOB_WAIT_INPUT_ACCEPT:
        if ((status & STATUS_SYS_READY) == 0U) {
            if (gateway_wait_or_drop("input_accept", status, GATEWAY_WAIT_ENGINE_POLLS) != 0) {
                return;
            }
            return;
        }
        if (gateway_log_block_details(&g_active_job)) {
            xil_printf("udp_crypto_gateway: state=%s ready status=0x%08lx offset=%u/%u\r\n",
                       job_state_name(g_job_state),
                       (unsigned long)status,
                       (unsigned)g_active_offset,
                       (unsigned)g_active_job.payload_len);
        }
        reset_job_wait_debug();
        g_job_state = JOB_PUSH_BLOCK;
        return;

    case JOB_PUSH_BLOCK:
        gateway_push_single_block(&g_active_job.payload[g_active_offset], g_active_offset);
        g_active_words_pushed = (uint8_t)((g_active_offset / 4U) + 4U);
        if (gateway_log_block_details(&g_active_job)) {
            xil_printf("udp_crypto_gateway: push_block done status_after=0x%08lx data0=%02x%02x%02x%02x\r\n",
                       (unsigned long)smoke_read32(REG_STATUS),
                       g_active_job.payload[g_active_offset + 0U],
                       g_active_job.payload[g_active_offset + 1U],
                       g_active_job.payload[g_active_offset + 2U],
                       g_active_job.payload[g_active_offset + 3U]);
        }
        g_job_state = JOB_WAIT_BLOCK_DONE;
        reset_job_wait_debug();
        return;

    case JOB_WAIT_BLOCK_DONE:
        if (((status & STATUS_SYS_READY) == 0U) || ((status & STATUS_TX_EMPTY) != 0U)) {
            if (gateway_wait_or_drop("block_done", status, GATEWAY_WAIT_BLOCK_POLLS) != 0) {
                return;
            }
            return;
        }

        if (gateway_log_block_details(&g_active_job)) {
            xil_printf("udp_crypto_gateway: state=%s block_done status=0x%08lx offset=%u/%u\r\n",
                       job_state_name(g_job_state),
                       (unsigned long)status,
                       (unsigned)g_active_offset,
                       (unsigned)g_active_job.payload_len);
        }
        reset_job_wait_debug();
        g_job_state = JOB_PULL_BLOCK;
        return;

    case JOB_PULL_BLOCK:
        if (gateway_pull_single_block_bounded(&g_active_job.ciphertext[g_active_offset], g_active_offset) != 0) {
            return;
        }
        if (gateway_log_block_details(&g_active_job)) {
            xil_printf("udp_crypto_gateway: pull_block done out0=%02x%02x%02x%02x\r\n",
                       g_active_job.ciphertext[g_active_offset + 0U],
                       g_active_job.ciphertext[g_active_offset + 1U],
                       g_active_job.ciphertext[g_active_offset + 2U],
                       g_active_job.ciphertext[g_active_offset + 3U]);
        }
        g_active_offset = (uint16_t)(g_active_offset + GATEWAY_BLOCK_BYTES);
        g_active_job.offset = g_active_offset;
        if (gateway_should_log_progress(&g_active_job, g_active_offset)) {
            xil_printf("udp_crypto_gateway: block_progress algo=%s local_port=%u offset=%u/%u blocks_done=%u\r\n",
                       gateway_algo_name(g_active_job.algo),
                       (unsigned)gateway_reply_local_port(&g_active_job),
                       (unsigned)g_active_offset,
                       (unsigned)g_active_job.payload_len,
                       (unsigned)(g_active_offset / GATEWAY_BLOCK_BYTES));
        }

        if (g_active_offset >= g_active_job.payload_len) {
            g_job_state = JOB_SEND_RESPONSE;
        } else {
            g_job_state = JOB_WAIT_INPUT_ACCEPT;
            reset_job_wait_debug();
        }
        return;

    case JOB_SEND_RESPONSE:
        xil_printf("udp_crypto_gateway: job_complete algo=%s blocks=%u len=%u\r\n",
                   gateway_algo_name(g_active_job.algo),
                   (unsigned)(g_active_job.payload_len / GATEWAY_BLOCK_BYTES),
                   (unsigned)g_active_job.payload_len);
        if (send_active_response() != 0) {
            g_stat_failures++;
            xil_printf("udp_crypto_gateway: response failed failures=%lu\r\n",
                       (unsigned long)g_stat_failures);
        }
        clear_active_job_state();
        return;

    default:
        g_job_state = JOB_IDLE;
        g_job_active = 0U;
        reset_job_wait_debug();
        return;
    }
}
#endif

void print_app_header(void)
{
    xil_printf("\n\r\n\r----- AX7020 UDP Crypto Gateway -----\n\r");
    xil_printf("UDP dst port 4660 = AES-128 ECB, 4661 = SM4, 4662 = control, 16-byte aligned payload only\n\r");
    xil_printf("Packets are queued in udp_recv() and processed asynchronously in main loop\n\r");
    xil_printf("CRYPTO_BASE_ADDR = 0x%08lx", (unsigned long)CRYPTO_BASE_ADDR);
#ifdef CRYPTO_BASE_FALLBACK
    xil_printf(" (fallback)");
#endif
    xil_printf("\n\r");
}

#if !UDP_GATEWAY_SMOKE_ONLY_BUILD
int start_application(void)
{
    err_t err;

    memset(g_queue, 0, sizeof(g_queue));
    memset(g_sessions, 0, sizeof(g_sessions));
    memset(&g_active_job, 0, sizeof(g_active_job));
    g_udp_pcb_aes = NULL;
    g_udp_pcb_sm4 = NULL;
    g_udp_pcb_ctrl = NULL;
    g_queue_head = 0U;
    g_queue_tail = 0U;
    g_queue_count = 0U;
    g_job_active = 0U;
    g_job_state = JOB_IDLE;
    reset_job_wait_debug();
    g_stat_drops_busy = 0U;
    g_stat_drops_invalid = 0U;
    g_stat_completed = 0U;
    g_stat_jobs_started = 0U;
    g_stat_failures = 0U;
    g_stat_rx_ctrl_ok = 0U;
    g_stat_rx_data_ok = 0U;
    g_stat_tx_ok = 0U;
    g_stat_drop_unauthorized = 0U;
    g_stat_drop_replay = 0U;
    g_stat_bind_fail = 0U;
    g_stat_lock_events = 0U;
    g_stat_crypto_timeout = 0U;
    g_stat_crypto_fail = 0U;
    g_next_session_id = 1U;

    xil_printf("udp_crypto_gateway: custom PL clock/reset path already prepared\r\n");
    dump_pl_registers();

    xil_printf("udp_crypto_gateway: REG_STATUS initial=0x%08lx\r\n",
               (unsigned long)HW_READ(REG_STATUS));

    g_udp_pcb_aes = udp_new_ip_type(IPADDR_TYPE_ANY);
    g_udp_pcb_sm4 = udp_new_ip_type(IPADDR_TYPE_ANY);
    g_udp_pcb_ctrl = udp_new_ip_type(IPADDR_TYPE_ANY);
    if ((g_udp_pcb_aes == NULL) || (g_udp_pcb_sm4 == NULL) || (g_udp_pcb_ctrl == NULL)) {
        xil_printf("udp_crypto_gateway: udp_new_ip_type failed aes=0x%08lx sm4=0x%08lx ctrl=0x%08lx\r\n",
                   (unsigned long)g_udp_pcb_aes,
                   (unsigned long)g_udp_pcb_sm4,
                   (unsigned long)g_udp_pcb_ctrl);
        return -1;
    }

    err = udp_bind(g_udp_pcb_aes, IP_ANY_TYPE, GATEWAY_UDP_PORT_AES);
    if (err != ERR_OK) {
        xil_printf("udp_crypto_gateway: udp_bind AES failed err=%d\r\n", (int)err);
        return -2;
    }

    err = udp_bind(g_udp_pcb_sm4, IP_ANY_TYPE, GATEWAY_UDP_PORT_SM4);
    if (err != ERR_OK) {
        xil_printf("udp_crypto_gateway: udp_bind SM4 failed err=%d\r\n", (int)err);
        return -3;
    }

    err = udp_bind(g_udp_pcb_ctrl, IP_ANY_TYPE, GATEWAY_UDP_PORT_CTRL);
    if (err != ERR_OK) {
        xil_printf("udp_crypto_gateway: udp_bind CTRL failed err=%d\r\n", (int)err);
        return -4;
    }

    xil_printf("udp_crypto_gateway: udp_bind AES ok pcb=0x%08lx local_port=%u\r\n",
               (unsigned long)g_udp_pcb_aes,
               (unsigned)g_udp_pcb_aes->local_port);
    xil_printf("udp_crypto_gateway: udp_bind SM4 ok pcb=0x%08lx local_port=%u\r\n",
               (unsigned long)g_udp_pcb_sm4,
               (unsigned)g_udp_pcb_sm4->local_port);
    xil_printf("udp_crypto_gateway: udp_bind CTRL ok pcb=0x%08lx local_port=%u\r\n",
               (unsigned long)g_udp_pcb_ctrl,
               (unsigned)g_udp_pcb_ctrl->local_port);

    udp_recv(g_udp_pcb_aes, udp_rx_callback, (void *)&g_listener_aes);
    udp_recv(g_udp_pcb_sm4, udp_rx_callback, (void *)&g_listener_sm4);
    udp_recv(g_udp_pcb_ctrl, udp_control_callback, NULL);
    xil_printf("UDP crypto gateway started @ ports %u(AES) %u(SM4) %u(CTRL)\r\n",
               (unsigned)GATEWAY_UDP_PORT_AES,
               (unsigned)GATEWAY_UDP_PORT_SM4,
               (unsigned)GATEWAY_UDP_PORT_CTRL);
    return 0;
}

int transfer_data(void)
{
    start_next_job_if_available();
    service_active_job();
    return 0;
}
#endif
