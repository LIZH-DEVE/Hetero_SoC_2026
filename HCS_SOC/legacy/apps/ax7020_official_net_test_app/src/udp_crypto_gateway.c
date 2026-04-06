#include <stdint.h>
#include <string.h>

#include "lwip/err.h"
#include "lwip/ip_addr.h"
#include "lwip/pbuf.h"
#include "lwip/udp.h"
#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"

#include "udp_crypto_gateway.h"

#define GATEWAY_UDP_PORT 4660U
#define GATEWAY_QUEUE_DEPTH 4U
#define GATEWAY_MAX_PAYLOAD_BYTES 1472U
#define JOB_WAIT_WARN_CYCLES 5000000UL

#define SLCR_UNLOCK_ADDR 0xF8000008U
#define SLCR_LOCK_ADDR   0xF8000004U
#define SLCR_UNLOCK_KEY  0x0000DF0DU
#define SLCR_LOCK_KEY    0x0000767BU

#define FPGA0_CLK_CTRL_ADDR    0xF8000170U
#define FPGA_CLK621_TRUE_ADDR  0xF80001C4U
#define FPGA_RST_CTRL_ADDR     0xF8000240U
#define FPGA_LVL_SHIFTER_ADDR  0xF8000900U

#if defined(XPAR_CRYPTO_ACCEL_AXI_0_BASEADDR)
#define CRYPTO_BASE_ADDR XPAR_CRYPTO_ACCEL_AXI_0_BASEADDR
#else
#define CRYPTO_BASE_ADDR 0x43C00000U
#define CRYPTO_BASE_FALLBACK 1
#endif
#define REG_CTRL      0x00U
#define REG_DATA_IN   0x04U
#define REG_STATUS    0x08U
#define REG_DATA_OUT  0x0CU
#define REG_KEY_0     0x10U

#define STATUS_SYS_READY 0x00000001U
#define STATUS_TX_EMPTY  0x00000002U

#define ALGO_AES      0U
#define MODE_ENCRYPT  1U

#define HW_WRITE(offset, data) Xil_Out32(CRYPTO_BASE_ADDR + (offset), (data))
#define HW_READ(offset)        Xil_In32(CRYPTO_BASE_ADDR + (offset))

typedef struct {
    ip_addr_t remote_ip;
    uint16_t remote_port;
    uint16_t payload_len;
    uint8_t payload[GATEWAY_MAX_PAYLOAD_BYTES];
    uint8_t ciphertext[GATEWAY_MAX_PAYLOAD_BYTES];
} gateway_request_t;

typedef enum {
    JOB_IDLE = 0,
    JOB_WAIT_ENGINE_READY,
    JOB_WAIT_INPUT_ACCEPT,
    JOB_WAIT_BLOCK_DONE
} gateway_job_state_t;

static struct udp_pcb *g_udp_pcb;
static gateway_request_t g_queue[GATEWAY_QUEUE_DEPTH];
static uint8_t g_queue_head;
static uint8_t g_queue_tail;
static uint8_t g_queue_count;
static gateway_request_t g_active_job;
static uint16_t g_active_offset;
static uint8_t g_job_active;
static gateway_job_state_t g_job_state = JOB_IDLE;
static uint32_t g_job_wait_cycles;
static uint8_t g_job_wait_reported;
static uint32_t g_stat_drops_busy;
static uint32_t g_stat_drops_invalid;
static uint32_t g_stat_completed;

static void mask_write32(uint32_t addr, uint32_t mask, uint32_t value)
{
    uint32_t cur = Xil_In32(addr);
    cur &= ~mask;
    cur |= (value & mask);
    Xil_Out32(addr, cur);
}

static void enable_custom_pl_path(void)
{
    Xil_Out32(SLCR_UNLOCK_ADDR, SLCR_UNLOCK_KEY);
    mask_write32(FPGA0_CLK_CTRL_ADDR, 0x03F03F30U, 0x00400800U);
    mask_write32(FPGA_CLK621_TRUE_ADDR, 0x00000001U, 0x00000001U);
    mask_write32(FPGA_LVL_SHIFTER_ADDR, 0x0000000FU, 0x0000000FU);
    mask_write32(FPGA_RST_CTRL_ADDR, 0xFFFFFFFFU, 0x00000000U);
    Xil_Out32(SLCR_LOCK_ADDR, SLCR_LOCK_KEY);
}

static void reset_job_wait_debug(void)
{
    g_job_wait_cycles = 0U;
    g_job_wait_reported = 0U;
}

static void report_job_wait_if_needed(uint32_t status)
{
    if (g_job_wait_reported) {
        return;
    }

    g_job_wait_cycles++;
    if (g_job_wait_cycles < JOB_WAIT_WARN_CYCLES) {
        return;
    }

    xil_printf("udp_crypto_gateway: wait state=%u status=0x%08lx offset=%u len=%u\r\n",
               (unsigned)g_job_state,
               (unsigned long)status,
               (unsigned)g_active_offset,
               (unsigned)g_active_job.payload_len);
    g_job_wait_reported = 1U;
}

static const uint8_t g_aes128_key[16] = {
    0x2B, 0x7E, 0x15, 0x16, 0x28, 0xAE, 0xD2, 0xA6,
    0xAB, 0xF7, 0x15, 0x88, 0x09, 0xCF, 0x4F, 0x3C
};

static void load_key_128(const uint8_t *key)
{
    int i;

    for (i = 0; i < 4; ++i) {
        uint32_t kv = ((uint32_t)key[i * 4] << 24) |
                      ((uint32_t)key[i * 4 + 1] << 16) |
                      ((uint32_t)key[i * 4 + 2] << 8) |
                      (uint32_t)key[i * 4 + 3];
        HW_WRITE(REG_KEY_0 + (uint32_t)((3 - i) * 4), kv);
    }
}

static void push_block_raw(const uint8_t *in_block)
{
    int i;

    for (i = 0; i < 4; ++i) {
        uint32_t din = ((uint32_t)in_block[i * 4] << 24) |
                       ((uint32_t)in_block[i * 4 + 1] << 16) |
                       ((uint32_t)in_block[i * 4 + 2] << 8) |
                       (uint32_t)in_block[i * 4 + 3];
        HW_WRITE(REG_DATA_IN, din);
    }
}

static void pull_block_raw(uint8_t *out_block)
{
    int i;

    for (i = 0; i < 4; ++i) {
        uint32_t dout = HW_READ(REG_DATA_OUT);
        out_block[i * 4] = (uint8_t)((dout >> 24) & 0xFFU);
        out_block[i * 4 + 1] = (uint8_t)((dout >> 16) & 0xFFU);
        out_block[i * 4 + 2] = (uint8_t)((dout >> 8) & 0xFFU);
        out_block[i * 4 + 3] = (uint8_t)(dout & 0xFFU);
    }
}

static int queue_push(const ip_addr_t *remote_ip, uint16_t remote_port, const uint8_t *payload, uint16_t payload_len)
{
    gateway_request_t *slot;

    if (g_queue_count >= GATEWAY_QUEUE_DEPTH) {
        return -1;
    }

    slot = &g_queue[g_queue_tail];
    memset(slot, 0, sizeof(*slot));
    ip_addr_copy(slot->remote_ip, *remote_ip);
    slot->remote_port = remote_port;
    slot->payload_len = payload_len;
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

static void udp_rx_callback(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
    uint16_t payload_len;
    uint8_t local_payload[GATEWAY_MAX_PAYLOAD_BYTES];

    (void)arg;
    (void)pcb;

    if (p == NULL) {
        return;
    }

    payload_len = (uint16_t)p->tot_len;
    if ((payload_len == 0U) ||
        (payload_len > GATEWAY_MAX_PAYLOAD_BYTES) ||
        ((payload_len & 0x0FU) != 0U)) {
        g_stat_drops_invalid++;
        xil_printf("udp_crypto_gateway: drop invalid len=%u\r\n", (unsigned)payload_len);
        pbuf_free(p);
        return;
    }

    (void)pbuf_copy_partial(p, local_payload, payload_len, 0U);
    pbuf_free(p);

    if (queue_push(addr, port, local_payload, payload_len) != 0) {
        g_stat_drops_busy++;
        xil_printf("udp_crypto_gateway: queue full len=%u\r\n", (unsigned)payload_len);
    } else {
        xil_printf("udp_crypto_gateway: queued len=%u from port=%u\r\n",
                   (unsigned)payload_len, (unsigned)port);
    }
}

static int send_active_response(void)
{
    struct pbuf *resp;
    err_t err;

    resp = pbuf_alloc(PBUF_TRANSPORT, g_active_job.payload_len, PBUF_RAM);
    if (resp == NULL) {
        xil_printf("udp_crypto_gateway: pbuf_alloc failed\r\n");
        return -1;
    }

    err = pbuf_take(resp, g_active_job.ciphertext, g_active_job.payload_len);
    if (err == ERR_OK) {
        err = udp_sendto(g_udp_pcb, resp, &g_active_job.remote_ip, g_active_job.remote_port);
    }
    pbuf_free(resp);

    if (err != ERR_OK) {
        xil_printf("udp_crypto_gateway: udp_sendto failed err=%d\r\n", (int)err);
        return -1;
    }

    g_stat_completed++;
    xil_printf("udp_crypto_gateway: response sent len=%u total=%lu\r\n",
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
    g_job_active = 1U;
    g_job_state = JOB_WAIT_ENGINE_READY;
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
            report_job_wait_if_needed(status);
            return;
        }
        reset_job_wait_debug();
        load_key_128(g_aes128_key);
        HW_WRITE(REG_CTRL, ((uint32_t)ALGO_AES & 0x01U) | (((uint32_t)MODE_ENCRYPT & 0x01U) << 1));
        g_job_state = JOB_WAIT_INPUT_ACCEPT;
        reset_job_wait_debug();
        return;

    case JOB_WAIT_INPUT_ACCEPT:
        if ((status & STATUS_SYS_READY) == 0U) {
            report_job_wait_if_needed(status);
            return;
        }
        reset_job_wait_debug();
        push_block_raw(&g_active_job.payload[g_active_offset]);
        g_job_state = JOB_WAIT_BLOCK_DONE;
        reset_job_wait_debug();
        return;

    case JOB_WAIT_BLOCK_DONE:
        if (((status & STATUS_SYS_READY) == 0U) || ((status & STATUS_TX_EMPTY) != 0U)) {
            report_job_wait_if_needed(status);
            return;
        }

        reset_job_wait_debug();
        pull_block_raw(&g_active_job.ciphertext[g_active_offset]);
        g_active_offset = (uint16_t)(g_active_offset + 16U);

        if (g_active_offset >= g_active_job.payload_len) {
            (void)send_active_response();
            memset(&g_active_job, 0, sizeof(g_active_job));
            g_job_active = 0U;
            g_job_state = JOB_IDLE;
            reset_job_wait_debug();
        } else {
            g_job_state = JOB_WAIT_ENGINE_READY;
            reset_job_wait_debug();
        }
        return;

    default:
        g_job_state = JOB_IDLE;
        g_job_active = 0U;
        reset_job_wait_debug();
        return;
    }
}

void print_app_header(void)
{
    xil_printf("\n\r\n\r----- AX7020 UDP Crypto Gateway -----\n\r");
    xil_printf("UDP dst port 4660, AES-128 ECB, 16-byte aligned payload only\n\r");
    xil_printf("Packets are queued in udp_recv() and processed asynchronously in main loop\n\r");
    xil_printf("CRYPTO_BASE_ADDR = 0x%08lx", (unsigned long)CRYPTO_BASE_ADDR);
#ifdef CRYPTO_BASE_FALLBACK
    xil_printf(" (fallback)");
#endif
    xil_printf("\n\r");
}

int start_application(void)
{
    err_t err;

    memset(g_queue, 0, sizeof(g_queue));
    memset(&g_active_job, 0, sizeof(g_active_job));
    g_queue_head = 0U;
    g_queue_tail = 0U;
    g_queue_count = 0U;
    g_job_active = 0U;
    g_job_state = JOB_IDLE;
    reset_job_wait_debug();
    g_stat_drops_busy = 0U;
    g_stat_drops_invalid = 0U;
    g_stat_completed = 0U;

    xil_printf("udp_crypto_gateway: enabling custom PL clock/reset path\r\n");
    enable_custom_pl_path();
    xil_printf("udp_crypto_gateway: REG_STATUS initial=0x%08lx\r\n",
               (unsigned long)HW_READ(REG_STATUS));

    g_udp_pcb = udp_new_ip_type(IPADDR_TYPE_ANY);
    if (g_udp_pcb == NULL) {
        xil_printf("udp_crypto_gateway: udp_new_ip_type failed\r\n");
        return -1;
    }

    err = udp_bind(g_udp_pcb, IP_ANY_TYPE, GATEWAY_UDP_PORT);
    if (err != ERR_OK) {
        xil_printf("udp_crypto_gateway: udp_bind failed err=%d\r\n", (int)err);
        return -2;
    }

    udp_recv(g_udp_pcb, udp_rx_callback, NULL);
    xil_printf("UDP crypto gateway started @ port %u\r\n", GATEWAY_UDP_PORT);
    return 0;
}

int transfer_data(void)
{
    start_next_job_if_available();
    service_active_job();
    return 0;
}
