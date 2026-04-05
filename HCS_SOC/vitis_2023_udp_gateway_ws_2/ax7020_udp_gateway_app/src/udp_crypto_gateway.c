#include <stdint.h>
#include <string.h>

#ifndef UDP_GATEWAY_SMOKE_ONLY_BUILD
#define UDP_GATEWAY_SMOKE_ONLY_BUILD 0
#endif

#ifndef UDP_GATEWAY_ENABLE_SHADOW_MIRROR
#define UDP_GATEWAY_ENABLE_SHADOW_MIRROR 0
#endif

#if UDP_GATEWAY_ENABLE_SHADOW_MIRROR
#define GATEWAY_MAYBE_UNUSED __attribute__((unused))
#else
#define GATEWAY_MAYBE_UNUSED
#endif

#if !UDP_GATEWAY_SMOKE_ONLY_BUILD
#include "lwip/err.h"
#include "lwip/ip_addr.h"
#include "lwip/pbuf.h"
#include "lwip/udp.h"
#endif
#include "sleep.h"
#include "xparameters.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_mmu.h"
#include "xil_printf.h"
#include "xuartps.h"
#include "xtime_l.h"

#include "udp_crypto_gateway.h"

#if !UDP_GATEWAY_SMOKE_ONLY_BUILD && UDP_GATEWAY_ENABLE_SHADOW_MIRROR
#include "dma_hw_regs.h"
#include "dma_mvp_ps_driver_ref.h"
#endif

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
#define GATEWAY_SESSION_TIMEOUT_MS 10000U
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
#define GATEWAY_SYNC_WINDOW_BLOCKS 2U

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
#define REG_WREADY_STALL_COUNT 0x30U

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
#define WRAP_REG_DROP_WRONG_PORT_COUNT 0xCCU
#define WRAP_REG_DROP_UNALIGNED_COUNT  0xD0U
#define WRAP_REG_ACL_CNT              0x44U
#define WRAP_REG_ACL_ADDR             0x60U
#define WRAP_REG_ACL_DATA0            0x64U
#define WRAP_REG_ACL_DATA1            0x68U
#define WRAP_REG_ACL_DATA2            0x6CU
#define WRAP_REG_ACL_DATA3            0x70U
#define WRAP_REG_DEVICE_DNA_LO         0xD4U
#define WRAP_REG_DEVICE_DNA_HI         0xD8U
#define WRAP_REG_DEVICE_DNA_STATUS     0xDCU
#define WRAP_REG_FASTPATH_STATUS     0xE0U
#define WRAP_REG_FASTPATH_HIT_COUNT  0xE4U
#define WRAP_REG_FASTPATH_FALLBACK_COUNT 0xE8U

#define GATEWAY_DEVICE_DNA_STATUS_VALID 0x00000001U
#define GATEWAY_DEVICE_DNA_FALLBACK 0x0000000041583702ULL
#define GATEWAY_SHADOW_CTRL_ACL_EN 0x00000080U
#define GATEWAY_SHADOW_ACL_WRITE_PULSE 0x00000100U
#define GATEWAY_SHADOW_ACL_CLEAR_PULSE 0x00000200U
#define GATEWAY_SHADOW_FASTPATH_EN 0x00000800U
#define GATEWAY_FASTPATH_STATUS_TXCAP_STORAGE_SHIFT 6U
#define GATEWAY_FASTPATH_STATUS_TXCAP_STORAGE_MASK 0x00000001U
#define GATEWAY_FASTPATH_STATUS_REASON_SHIFT 2U
#define GATEWAY_FASTPATH_STATUS_REASON_MASK 0x0000000FU
#define GATEWAY_FASTPATH_REASON_IDLE 0U
#define GATEWAY_FASTPATH_REASON_HIT 1U
#define GATEWAY_FASTPATH_REASON_DISABLED 2U
#define GATEWAY_FASTPATH_REASON_ACL_DROP 3U
#define GATEWAY_FASTPATH_REASON_TX_BUSY 4U
#define GATEWAY_FASTPATH_REASON_FRAME_INVALID 5U
#define GATEWAY_STATUS_AUTH_MASK_MASK        0x000000FFU
#define GATEWAY_STATUS_DROP_REASON_SHIFT     8U
#define GATEWAY_STATUS_LOCK_REASON_SHIFT     12U
#define GATEWAY_STATUS_ACL_HIT_SEEN_SHIFT    16U
#define GATEWAY_STATUS_REPLAY_SEEN_SHIFT     17U
#define GATEWAY_STATUS_TIMEOUT_SEEN_SHIFT    18U
#define GATEWAY_STATUS_REAUTH_SEEN_SHIFT     19U

#define GATEWAY_NET_CFG_ENABLE     0x00000001U
#define GATEWAY_NET_CFG_INJECT_SEL 0x00000002U
#define GATEWAY_NET_CFG_ARP_ENABLE 0x00000004U
#define GATEWAY_LOCAL_IP_WORD      0xC0A80114U
#define GATEWAY_LOCAL_MAC_LO_WORD  0x35000120U
#define GATEWAY_LOCAL_MAC_HI_WORD  0x0000020AU

#define STATUS_SYS_READY 0x00000001U
#define STATUS_TX_EMPTY  0x00000002U

#define GATEWAY_UART_U32(value) ((unsigned)((uint32_t)(value)))
#define GATEWAY_UART_ADDR(value) ((unsigned)((uintptr_t)(value)))

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
#define GATEWAY_CTRL_MSG_ACL_WRITE 7U
#define GATEWAY_CTRL_MSG_ACL_CLEAR 8U
#define GATEWAY_CTRL_MSG_ACL_STATUS 9U

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
#define GATEWAY_ACL_TUPLE_PAYLOAD_BYTES 13U

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
    uint64_t device_dna;
    uint32_t binding_id;
    uint32_t highest_seq_id;
    uint32_t replay_window;
    uint32_t last_active_ms;
    uint8_t effective_key_aes[16];
    uint8_t effective_key_sm4[16];
} gateway_session_t;

typedef struct {
    uint8_t valid;
    uint8_t algo;
    uint16_t reserved;
    uint32_t session_id;
    uint32_t ctrl_word;
    uint8_t effective_key[16];
} gateway_hw_sync_cache_t;

typedef struct {
    uint32_t status_reads_total;
    uint32_t enqueue_count;
    uint32_t drain_count;
    uint32_t scheduler_idle_spins_peak;
    uint32_t inflight_high_watermark;
    uint32_t wready_stall_cnt_delta;
} gateway_hw_sync_diag_t;

typedef enum {
    GATEWAY_DROP_REASON_NONE = 0,
    GATEWAY_DROP_REASON_INVALID = 1,
    GATEWAY_DROP_REASON_UNAUTHORIZED = 2,
    GATEWAY_DROP_REASON_REPLAY = 3,
    GATEWAY_DROP_REASON_ACL = 4,
} gateway_drop_reason_t;

typedef enum {
    GATEWAY_LOCK_REASON_NONE = 0,
    GATEWAY_LOCK_REASON_MANUAL = 1,
    GATEWAY_LOCK_REASON_AUTH_THRESHOLD = 2,
    GATEWAY_LOCK_REASON_REPLAY_THRESHOLD = 3,
} gateway_lock_reason_t;

static struct udp_pcb *g_udp_pcb_aes;
static struct udp_pcb *g_udp_pcb_sm4;
static struct udp_pcb *g_udp_pcb_ctrl;
static XUartPs g_uart;
static gateway_request_t g_queue[GATEWAY_QUEUE_DEPTH];
static gateway_session_t g_sessions[GATEWAY_MAX_SESSIONS];
static gateway_hw_sync_cache_t g_hw_sync_cache;
static gateway_hw_sync_diag_t g_hw_sync_diag_last;
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
static gateway_drop_reason_t g_last_drop_reason;
static gateway_lock_reason_t g_last_lock_reason;
static uint8_t g_diag_acl_hit_seen;
static uint8_t g_diag_replay_seen;
static uint8_t g_diag_timeout_seen;
static uint8_t g_diag_reauth_seen;
static uint8_t g_diag_reauth_pending;
static uint32_t g_next_session_id = 1U;
static uint8_t g_active_words_pushed;
static uint8_t g_active_words_pulled;
static uint8_t g_bench_input[GATEWAY_MAX_PAYLOAD_BYTES];
static uint8_t g_bench_sw_output[GATEWAY_MAX_PAYLOAD_BYTES];
static uint8_t g_bench_hw_output[GATEWAY_MAX_PAYLOAD_BYTES];
static const gateway_listener_context_t g_listener_aes = { GATEWAY_ALGO_AES, GATEWAY_UDP_PORT_AES };
static const gateway_listener_context_t g_listener_sm4 = { GATEWAY_ALGO_SM4, GATEWAY_UDP_PORT_SM4 };
static const char *gateway_algo_name(gateway_algo_t algo);

#if UDP_GATEWAY_ENABLE_SHADOW_MIRROR
#define GATEWAY_SHADOW_QUEUE_DEPTH GATEWAY_QUEUE_DEPTH
#define GATEWAY_SHADOW_WORD_BYTES 4U
#define GATEWAY_SHADOW_RING_ENTRY_COUNT 2U
#define GATEWAY_SHADOW_POLL_TIMEOUT 3000000U
#define GATEWAY_SHADOW_FRAME_HEADER_WORDS 11U
#define GATEWAY_SHADOW_INJ_ARM_CTRL 1U
#define GATEWAY_SHADOW_HALT_LOG_ONCE 1U
#define GATEWAY_SHADOW_MILESTONE_LIVE_CTRL    0x01U
#define GATEWAY_SHADOW_MILESTONE_LIVE_AES     0x02U
#define GATEWAY_SHADOW_MILESTONE_LIVE_SM4     0x04U
#define GATEWAY_SHADOW_MILESTONE_SHADOW_AES   0x08U
#define GATEWAY_SHADOW_MILESTONE_SHADOW_SM4   0x10U
#define GATEWAY_SHADOW_MILESTONE_INVALID_SKIP 0x20U
#define GATEWAY_SHADOW_MILESTONE_ALL ( \
    GATEWAY_SHADOW_MILESTONE_LIVE_CTRL | \
    GATEWAY_SHADOW_MILESTONE_LIVE_AES | \
    GATEWAY_SHADOW_MILESTONE_LIVE_SM4 | \
    GATEWAY_SHADOW_MILESTONE_SHADOW_AES | \
    GATEWAY_SHADOW_MILESTONE_SHADOW_SM4 | \
    GATEWAY_SHADOW_MILESTONE_INVALID_SKIP)

#if defined(XPAR_DMA_GATEWAY_HYBRID_0_BASEADDR)
#define GATEWAY_SHADOW_DMA_BASEADDR XPAR_DMA_GATEWAY_HYBRID_0_BASEADDR
#elif defined(XPAR_DMA_GATEWAY_HYBRID_BOARD_WRAPPER_0_BASEADDR)
#define GATEWAY_SHADOW_DMA_BASEADDR XPAR_DMA_GATEWAY_HYBRID_BOARD_WRAPPER_0_BASEADDR
#else
#define GATEWAY_SHADOW_DMA_BASEADDR 0x40001000U
#endif

#define GATEWAY_SHADOW_CTRL_BASEADDR WRAPPER_BASE_ADDR
#define GATEWAY_BENCH_DMA_RING_ENTRY_COUNT 2048U
#define GATEWAY_BENCH_DMA_USABLE_RING_ENTRIES (GATEWAY_BENCH_DMA_RING_ENTRY_COUNT - 1U)
#define GATEWAY_BENCH_DMA_POLL_TIMEOUT 3000000U
#define GATEWAY_BENCH_DMA_CTRL_REG DMA_CSR_CTRL
#define GATEWAY_BENCH_DMA_LOOPBACK_MODE_REG DMA_CSR_LOOPBACK_MODE
#define GATEWAY_BENCH_DMA_KEY0_REG 0x28U
#define GATEWAY_BENCH_DMA_KEY1_REG 0x2CU
#define GATEWAY_BENCH_DMA_KEY2_REG 0x30U
#define GATEWAY_BENCH_DMA_KEY3_REG 0x34U
#define GATEWAY_BENCH_DMA_KEY4_REG 0x74U
#define GATEWAY_BENCH_DMA_KEY5_REG 0x78U
#define GATEWAY_BENCH_DMA_KEY6_REG 0x7CU
#define GATEWAY_BENCH_DMA_KEY7_REG 0x80U

typedef enum {
    GATEWAY_SHADOW_RUN_DISABLED = 0U,
    GATEWAY_SHADOW_RUN_READY = 1U,
    GATEWAY_SHADOW_RUN_ACTIVE = 2U,
    GATEWAY_SHADOW_RUN_HALTED = 3U
} gateway_shadow_run_state_t;

typedef enum {
    GATEWAY_SHADOW_HALT_REASON_NONE = 0U,
    GATEWAY_SHADOW_HALT_REASON_POLL_TIMEOUT = 1U
} gateway_shadow_halt_reason_t;

typedef enum {
    GATEWAY_SHADOW_JOB_FREE = 0U,
    GATEWAY_SHADOW_JOB_QUEUED = 1U,
    GATEWAY_SHADOW_JOB_ACTIVE = 2U,
    GATEWAY_SHADOW_JOB_DONE = 3U,
    GATEWAY_SHADOW_JOB_FAILED = 4U
} gateway_shadow_job_state_t;

typedef struct {
    gateway_algo_t algo;
    uint16_t local_port;
    uint16_t remote_port;
    uint16_t payload_len;
    uint16_t expected_actual_len;
    uint16_t frame_word_count;
    uint8_t payload_slot_idx;
    uint8_t state;
    uint16_t actual_len;
    uint16_t ring_hw_head;
    uint16_t ring_sw_tail;
    uint32_t status;
    uint32_t dma_status;
    uint32_t csw;
    uint32_t remote_ip;
    uint32_t acl_count_base;
    uint32_t fastpath_hit_count_base;
    uint32_t fastpath_fallback_count_base;
} gateway_shadow_job_t;

typedef struct {
    uint32_t accepted;
    uint32_t skip_busy;
    uint32_t skipped_halted;
    uint32_t submit_fail;
    uint32_t poll_timeout;
    uint32_t timeout_halt_count;
    uint32_t compare_fail;
    uint32_t pass;
} gateway_shadow_stats_t;

typedef struct {
    dma_ring_desc_t ring[GATEWAY_SHADOW_RING_ENTRY_COUNT];
} gateway_shadow_desc_region_t;

typedef struct {
    uint32_t words[GATEWAY_MAX_PAYLOAD_BYTES / GATEWAY_SHADOW_WORD_BYTES];
} gateway_shadow_dma_region_t;

typedef struct {
    dma_ring_desc_t ring[GATEWAY_BENCH_DMA_RING_ENTRY_COUNT];
} gateway_bench_dma_desc_region_t;

typedef struct {
    uint8_t payload[GATEWAY_MAX_PAYLOAD_BYTES];
} gateway_bench_dma_src_region_t;

typedef struct {
    uint8_t payload[GATEWAY_BENCH_DMA_USABLE_RING_ENTRIES * GATEWAY_MAX_PAYLOAD_BYTES];
} gateway_bench_dma_dst_region_t;

static uint8_t g_shadow_payload_pool[GATEWAY_SHADOW_QUEUE_DEPTH][GATEWAY_MAX_PAYLOAD_BYTES];
static gateway_shadow_job_t g_shadow_queue[GATEWAY_SHADOW_QUEUE_DEPTH];
static uint8_t g_shadow_slot_in_use[GATEWAY_SHADOW_QUEUE_DEPTH];
static uint8_t g_shadow_pending_slots[GATEWAY_SHADOW_QUEUE_DEPTH];
static uint8_t g_shadow_pending_head;
static uint8_t g_shadow_pending_tail;
static uint8_t g_shadow_pending_count;
static uint8_t g_shadow_active_slot_valid;
static uint8_t g_shadow_active_slot_idx;
static gateway_shadow_desc_region_t g_shadow_desc_region __attribute__((aligned(DMA_ALIGNMENT_BYTES)));
static gateway_shadow_dma_region_t g_shadow_dma_region __attribute__((aligned(DMA_ALIGNMENT_BYTES)));
static gateway_bench_dma_desc_region_t g_bench_dma_desc_region __attribute__((aligned(DMA_ALIGNMENT_BYTES)));
static gateway_bench_dma_src_region_t g_bench_dma_src_region __attribute__((aligned(DMA_ALIGNMENT_BYTES)));
static gateway_bench_dma_dst_region_t g_bench_dma_dst_region __attribute__((aligned(DMA_ALIGNMENT_BYTES)));
static dma_ring_ctx_t g_shadow_ring_ctx;
static dma_ring_ctx_t g_bench_dma_ring_ctx;
static gateway_shadow_run_state_t g_shadow_run_state = GATEWAY_SHADOW_RUN_DISABLED;
static gateway_shadow_halt_reason_t g_shadow_halt_reason = GATEWAY_SHADOW_HALT_REASON_NONE;
static gateway_shadow_stats_t g_shadow_stats;
static uint32_t g_shadow_last_timeout_slot;
static uint32_t g_shadow_last_timeout_status;
static uint32_t g_shadow_last_timeout_actual_len;
static uint32_t g_shadow_last_timeout_csw;
static uint32_t g_shadow_last_timeout_hw_head;
static uint32_t g_shadow_last_timeout_sw_tail;
static uint8_t g_shadow_halt_logged;
static uint32_t g_shadow_milestone_mask;
static uint8_t g_shadow_pass_reported;
static uint32_t g_shadow_frame_words[GATEWAY_SHADOW_FRAME_HEADER_WORDS + (GATEWAY_MAX_PAYLOAD_BYTES / GATEWAY_SHADOW_WORD_BYTES)];
#endif

typedef enum {
    GATEWAY_BACKEND_KIND_DIRECT_MMIO = 0U,
    GATEWAY_BACKEND_KIND_DMA_PROBE = 1U,
} gateway_backend_kind_t;

typedef uint32_t gateway_backend_caps_t;

#define GATEWAY_BACKEND_CAP_CRYPTO_SYNC 0x00000001U
#define GATEWAY_BACKEND_CAP_DMA_PROBE    0x00000002U
#define GATEWAY_BACKEND_ERR_NOT_SUPPORTED (-95)

/* Keep backend access behind a capability-aware shim so the gateway talks to
 * named backend operations instead of raw register helpers. */
typedef struct {
    gateway_backend_kind_t kind;
    gateway_backend_caps_t caps;
    uint32_t (*read32)(uint32_t offset);
    void (*write32)(uint32_t offset, uint32_t value);
    int (*probe_init)(void);
    int (*probe_submit_frame)(const uint8_t *frame, uint16_t frame_len);
    int (*probe_poll_done)(void);
    int (*probe_read_result)(uint16_t *actual_len, uint32_t *status);
    void (*probe_reset)(void);
} gateway_mmio_backend_t;

typedef gateway_mmio_backend_t gateway_backend_ops_t;

static uint32_t gateway_mmio_backend_read32(uint32_t offset);
static void gateway_mmio_backend_write32(uint32_t offset, uint32_t value);
static int gateway_dma_probe_backend_probe_init(void);
static int gateway_dma_probe_backend_submit_frame(const uint8_t *frame, uint16_t frame_len);
static int gateway_dma_probe_backend_poll_done(void);
static int gateway_dma_probe_backend_read_result(uint16_t *actual_len, uint32_t *status);
static void gateway_dma_probe_backend_reset(void);

static const gateway_backend_ops_t g_gateway_direct_mmio_backend = {
    GATEWAY_BACKEND_KIND_DIRECT_MMIO,
    GATEWAY_BACKEND_CAP_CRYPTO_SYNC,
    gateway_mmio_backend_read32,
    gateway_mmio_backend_write32,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
};

static const gateway_backend_ops_t g_gateway_dma_probe_backend = {
    GATEWAY_BACKEND_KIND_DMA_PROBE,
    GATEWAY_BACKEND_CAP_DMA_PROBE,
    gateway_mmio_backend_read32,
    gateway_mmio_backend_write32,
    gateway_dma_probe_backend_probe_init,
    gateway_dma_probe_backend_submit_frame,
    gateway_dma_probe_backend_poll_done,
    gateway_dma_probe_backend_read_result,
    gateway_dma_probe_backend_reset
};

static const gateway_backend_ops_t *g_gateway_backend = &g_gateway_direct_mmio_backend;

static void gateway_backend_select(const gateway_backend_ops_t *backend)
{
    if (backend != NULL) {
        g_gateway_backend = backend;
    }
}

static void gateway_backend_select_direct_mmio(void)
{
    gateway_backend_select(&g_gateway_direct_mmio_backend);
}

static void gateway_backend_select_dma_probe(void)
{
    gateway_backend_select(&g_gateway_dma_probe_backend);
}

static uint32_t gateway_backend_read32(uint32_t offset)
{
    return g_gateway_backend->read32(offset);
}

static void gateway_backend_write32(uint32_t offset, uint32_t value)
{
    g_gateway_backend->write32(offset, value);
}

static uint32_t gateway_backend_read_status(void)
{
    return gateway_backend_read32(REG_STATUS);
}

static void gateway_backend_write_ctrl(uint32_t value)
{
    gateway_backend_write32(REG_CTRL, value);
}

static void gateway_backend_write_data_in(uint32_t value)
{
    gateway_backend_write32(REG_DATA_IN, value);
}

static uint32_t gateway_backend_read_data_out(void)
{
    return gateway_backend_read32(REG_DATA_OUT);
}

static uint32_t gateway_backend_read_wready_stall_count(void)
{
    return gateway_backend_read32(REG_WREADY_STALL_COUNT);
}

static void gateway_backend_write_key_word(uint32_t offset, uint32_t value)
{
    gateway_backend_write32(offset, value);
}

static gateway_backend_kind_t gateway_backend_kind(void)
{
    return g_gateway_backend->kind;
}

static gateway_backend_caps_t gateway_backend_caps(void)
{
    return g_gateway_backend->caps;
}

static int gateway_backend_supports(gateway_backend_caps_t caps)
{
    return ((gateway_backend_caps() & caps) == caps) ? 1 : 0;
}

static int gateway_backend_require(gateway_backend_caps_t caps, const char *op_name)
{
    if (gateway_backend_supports(caps)) {
        return 0;
    }

    xil_printf("udp_crypto_gateway: backend op=%s not supported kind=%u caps=0x%08x need=0x%08x\r\n",
               op_name,
               (unsigned)gateway_backend_kind(),
               GATEWAY_UART_U32(gateway_backend_caps()),
               GATEWAY_UART_U32(caps));
    return GATEWAY_BACKEND_ERR_NOT_SUPPORTED;
}

static uint32_t gateway_mmio_backend_read32(uint32_t offset)
{
    DATA_SYNC;
    INST_SYNC;
    return HW_READ(offset);
}

static void gateway_mmio_backend_write32(uint32_t offset, uint32_t value)
{
    DATA_SYNC;
    HW_WRITE(offset, value);
    DATA_SYNC;
    INST_SYNC;
}

static int gateway_dma_probe_backend_probe_init(void)
{
    return -1;
}

static int gateway_dma_probe_backend_submit_frame(const uint8_t *frame, uint16_t frame_len)
{
    (void)frame;
    (void)frame_len;
    return -1;
}

static int gateway_dma_probe_backend_poll_done(void)
{
    return -1;
}

static int gateway_dma_probe_backend_read_result(uint16_t *actual_len, uint32_t *status)
{
    if (actual_len != NULL) {
        *actual_len = 0U;
    }
    if (status != NULL) {
        *status = 0U;
    }
    return -1;
}

static void gateway_dma_probe_backend_reset(void)
{
}

#if UDP_GATEWAY_ENABLE_SHADOW_MIRROR
static void gateway_shadow_mark_milestone(uint32_t milestone)
{
    g_shadow_milestone_mask |= milestone;
    if ((g_shadow_pass_reported == 0U) &&
        ((g_shadow_milestone_mask & GATEWAY_SHADOW_MILESTONE_ALL) == GATEWAY_SHADOW_MILESTONE_ALL)) {
        g_shadow_pass_reported = 1U;
        xil_printf("UDP gateway shadow mirror PASS\r\n");
    }
}

static inline void gateway_shadow_wrap_write32(uint32_t offset, uint32_t value)
{
    Xil_Out32((UINTPTR)(GATEWAY_SHADOW_CTRL_BASEADDR + offset), value);
}

static inline uint32_t gateway_shadow_wrap_read32(uint32_t offset)
{
    return Xil_In32((UINTPTR)(GATEWAY_SHADOW_CTRL_BASEADDR + offset));
}

static inline uint32_t gateway_wrap_read32(uint32_t offset)
{
    return gateway_shadow_wrap_read32(offset);
}

static uint32_t gateway_shadow_payload_word(const uint8_t *payload, uint32_t word_idx)
{
    uint32_t base = word_idx * GATEWAY_SHADOW_WORD_BYTES;
    return ((uint32_t)payload[base + 0U] << 24) |
           ((uint32_t)payload[base + 1U] << 16) |
           ((uint32_t)payload[base + 2U] << 8) |
           (uint32_t)payload[base + 3U];
}

static void gateway_shadow_prepare_mmio(void)
{
    static uint8_t prepared;

    if (prepared != 0U) {
        return;
    }

    Xil_SetTlbAttributes((INTPTR)GATEWAY_SHADOW_CTRL_BASEADDR, STRONG_ORDERED);
    Xil_SetTlbAttributes((INTPTR)GATEWAY_SHADOW_DMA_BASEADDR, STRONG_ORDERED);
    DATA_SYNC;
    INST_SYNC;
    prepared = 1U;
}

static void gateway_shadow_configure_wrapper(void)
{
    uint32_t ctrl = gateway_shadow_wrap_read32(WRAP_REG_CTRL);

    gateway_shadow_wrap_write32(WRAP_REG_CTRL, ctrl | GATEWAY_SHADOW_FASTPATH_EN);
    gateway_shadow_wrap_write32(WRAP_REG_NET_CFG0,
                                GATEWAY_NET_CFG_ENABLE | GATEWAY_NET_CFG_INJECT_SEL | GATEWAY_NET_CFG_ARP_ENABLE);
    gateway_shadow_wrap_write32(WRAP_REG_NET_LOCAL_IP, GATEWAY_LOCAL_IP_WORD);
    gateway_shadow_wrap_write32(WRAP_REG_NET_LOCAL_MAC_LO, GATEWAY_LOCAL_MAC_LO_WORD);
    gateway_shadow_wrap_write32(WRAP_REG_NET_LOCAL_MAC_HI, GATEWAY_LOCAL_MAC_HI_WORD);
    gateway_shadow_wrap_write32(WRAP_REG_INJ_CTRL, GATEWAY_SHADOW_INJ_ARM_CTRL);
    gateway_shadow_wrap_write32(WRAP_REG_TXCAP_CTRL, 1U);
    DATA_SYNC;
}

static uint16_t gateway_shadow_acl_hash_tuple(uint32_t src_ip,
                                              uint16_t src_port,
                                              uint32_t dst_ip,
                                              uint16_t dst_port,
                                              uint8_t protocol)
{
    uint16_t h;

    h = (uint16_t)(dst_port ^
                   (uint16_t)((dst_ip >> 16) & 0xFFFFU) ^
                   (uint16_t)(dst_ip & 0xFFFFU) ^
                   src_port ^
                   (uint16_t)((src_ip >> 16) & 0xFFFFU) ^
                   (uint16_t)(src_ip & 0xFFFFU) ^
                   (uint16_t)protocol);
    h ^= (uint16_t)(((h & 0x00FFU) << 8) | ((h >> 8) & 0x00FFU));
    h ^= 0x9E37U;
    return (uint16_t)((h ^
                       (uint16_t)(((h & 0x07FFU) << 5) | ((h >> 11) & 0x001FU)) ^
                       (uint16_t)(h >> 3)) & 0x0FFFU);
}

static void gateway_shadow_acl_pack_rule_regs(uint32_t src_ip,
                                              uint16_t src_port,
                                              uint32_t dst_ip,
                                              uint16_t dst_port,
                                              uint8_t protocol,
                                              uint32_t *data0_out,
                                              uint32_t *data1_out,
                                              uint32_t *data2_out,
                                              uint32_t *data3_out)
{
    uint32_t data0 = (((uint32_t)(dst_ip & 0xFFFFU)) << 16) | (uint32_t)dst_port;
    uint32_t data1 = (((uint32_t)src_port) << 16) | ((dst_ip >> 16) & 0xFFFFU);
    uint32_t data2 = src_ip;
    uint32_t data3 = (uint32_t)protocol;

    *data0_out = data0;
    *data1_out = data1;
    *data2_out = data2;
    *data3_out = data3;
}

static int gateway_shadow_acl_write_rule(uint32_t src_ip,
                                         uint16_t src_port,
                                         uint32_t dst_ip,
                                         uint16_t dst_port,
                                         uint8_t protocol)
{
    uint16_t rule_addr;
    uint32_t data0;
    uint32_t data1;
    uint32_t data2;
    uint32_t data3;
    uint32_t ctrl;

    rule_addr = gateway_shadow_acl_hash_tuple(src_ip, src_port, dst_ip, dst_port, protocol);
    gateway_shadow_acl_pack_rule_regs(src_ip, src_port, dst_ip, dst_port, protocol, &data0, &data1, &data2, &data3);
    gateway_shadow_wrap_write32(WRAP_REG_ACL_ADDR, (uint32_t)rule_addr);
    gateway_shadow_wrap_write32(WRAP_REG_ACL_DATA0, data0);
    gateway_shadow_wrap_write32(WRAP_REG_ACL_DATA1, data1);
    gateway_shadow_wrap_write32(WRAP_REG_ACL_DATA2, data2);
    gateway_shadow_wrap_write32(WRAP_REG_ACL_DATA3, data3 | GATEWAY_SHADOW_ACL_WRITE_PULSE);
    ctrl = gateway_shadow_wrap_read32(WRAP_REG_CTRL);
    gateway_shadow_wrap_write32(WRAP_REG_CTRL, ctrl | GATEWAY_SHADOW_CTRL_ACL_EN);
    DATA_SYNC;
    return 0;
}

static void gateway_shadow_acl_clear_all(void)
{
    uint32_t ctrl = gateway_shadow_wrap_read32(WRAP_REG_CTRL);

    gateway_shadow_wrap_write32(WRAP_REG_CTRL, ctrl & ~GATEWAY_SHADOW_CTRL_ACL_EN);
    gateway_shadow_wrap_write32(WRAP_REG_ACL_CNT, 0U);
    gateway_shadow_wrap_write32(WRAP_REG_ACL_ADDR, 0U);
    gateway_shadow_wrap_write32(WRAP_REG_ACL_DATA0, 0U);
    gateway_shadow_wrap_write32(WRAP_REG_ACL_DATA1, 0U);
    gateway_shadow_wrap_write32(WRAP_REG_ACL_DATA2, 0U);
    gateway_shadow_wrap_write32(WRAP_REG_ACL_DATA3, GATEWAY_SHADOW_ACL_CLEAR_PULSE);
    DATA_SYNC;
}

static void gateway_shadow_prepare_ring(void)
{
    memset(&g_shadow_desc_region, 0, sizeof(g_shadow_desc_region));
    memset(&g_shadow_dma_region, 0, sizeof(g_shadow_dma_region));
    dma_ring_init(&g_shadow_ring_ctx,
                  GATEWAY_SHADOW_DMA_BASEADDR,
                  &g_shadow_desc_region.ring[0],
                  (uint32_t)(uintptr_t)&g_shadow_desc_region.ring[0],
                  GATEWAY_SHADOW_RING_ENTRY_COUNT);
    dma_ring_soft_reset(&g_shadow_ring_ctx);
    dma_ring_init(&g_shadow_ring_ctx,
                  GATEWAY_SHADOW_DMA_BASEADDR,
                  &g_shadow_desc_region.ring[0],
                  (uint32_t)(uintptr_t)&g_shadow_desc_region.ring[0],
                  GATEWAY_SHADOW_RING_ENTRY_COUNT);
}

static int gateway_shadow_init_runtime(void)
{
    gateway_shadow_prepare_mmio();
    memset(g_shadow_payload_pool, 0, sizeof(g_shadow_payload_pool));
    memset(g_shadow_queue, 0, sizeof(g_shadow_queue));
    memset(g_shadow_slot_in_use, 0, sizeof(g_shadow_slot_in_use));
    memset(g_shadow_pending_slots, 0, sizeof(g_shadow_pending_slots));
    memset(&g_shadow_stats, 0, sizeof(g_shadow_stats));
    g_shadow_pending_head = 0U;
    g_shadow_pending_tail = 0U;
    g_shadow_pending_count = 0U;
    g_shadow_active_slot_valid = 0U;
    g_shadow_active_slot_idx = 0U;
    g_shadow_halt_reason = GATEWAY_SHADOW_HALT_REASON_NONE;
    g_shadow_last_timeout_slot = 0U;
    g_shadow_last_timeout_status = 0U;
    g_shadow_last_timeout_actual_len = 0U;
    g_shadow_last_timeout_csw = 0U;
    g_shadow_last_timeout_hw_head = 0U;
    g_shadow_last_timeout_sw_tail = 0U;
    g_shadow_halt_logged = 0U;
    g_shadow_milestone_mask = 0U;
    g_shadow_pass_reported = 0U;
    gateway_shadow_prepare_ring();
    gateway_shadow_configure_wrapper();
    g_shadow_run_state = GATEWAY_SHADOW_RUN_READY;
    return 0;
}

static int gateway_shadow_allocate_slot(uint8_t *slot_out)
{
    uint32_t slot_idx;

    for (slot_idx = 0U; slot_idx < GATEWAY_SHADOW_QUEUE_DEPTH; ++slot_idx) {
        if (g_shadow_slot_in_use[slot_idx] == 0U) {
            g_shadow_slot_in_use[slot_idx] = 1U;
            *slot_out = (uint8_t)slot_idx;
            return 0;
        }
    }

    return -1;
}

static void gateway_shadow_release_slot(uint8_t slot_idx)
{
    if (slot_idx >= GATEWAY_SHADOW_QUEUE_DEPTH) {
        return;
    }

    memset(g_shadow_payload_pool[slot_idx], 0, sizeof(g_shadow_payload_pool[slot_idx]));
    memset(&g_shadow_queue[slot_idx], 0, sizeof(g_shadow_queue[slot_idx]));
    g_shadow_slot_in_use[slot_idx] = 0U;
}

static uint32_t gateway_shadow_buffer_capacity(uint16_t expected_actual_len)
{
    uint32_t capacity = (uint32_t)expected_actual_len;

    if (capacity == 0U) {
        return 0U;
    }

    capacity = (capacity + (DMA_RAW_COPY_LEN_MULTIPLE - 1U)) &
               ~(DMA_RAW_COPY_LEN_MULTIPLE - 1U);
    return capacity;
}

static int gateway_shadow_build_frame(uint8_t payload_slot_idx,
                                      uint16_t local_port,
                                      uint32_t remote_ip,
                                      uint16_t remote_port,
                                      uint16_t payload_len,
                                      uint32_t *frame_word_count_out)
{
    uint32_t payload_words;
    uint32_t frame_word_count;
    uint32_t word_idx;

    if ((payload_len == 0U) || (payload_len > GATEWAY_MAX_PAYLOAD_BYTES)) {
        return -1;
    }
    if ((payload_len & (GATEWAY_SHADOW_WORD_BYTES - 1U)) != 0U) {
        return -2;
    }

    payload_words = payload_len / GATEWAY_SHADOW_WORD_BYTES;
    frame_word_count = GATEWAY_SHADOW_FRAME_HEADER_WORDS + payload_words;
    memset(g_shadow_frame_words, 0, sizeof(g_shadow_frame_words));

    g_shadow_frame_words[0] = 0x020ABBCCU;
    g_shadow_frame_words[1] = 0xDDEE020AU;
    g_shadow_frame_words[2] = GATEWAY_LOCAL_MAC_LO_WORD;
    g_shadow_frame_words[3] = 0x08000000U;
    g_shadow_frame_words[4] = (((uint32_t)(20U + 8U + payload_len)) << 16) | 0x0005U;
    g_shadow_frame_words[5] = 0x00000000U;
    g_shadow_frame_words[6] = 0x40110000U;
    g_shadow_frame_words[7] = remote_ip;
    g_shadow_frame_words[8] = GATEWAY_LOCAL_IP_WORD;
    g_shadow_frame_words[9] = ((uint32_t)local_port << 16) | remote_port;
    g_shadow_frame_words[10] = (uint32_t)(payload_len + 8U);

    for (word_idx = 0U; word_idx < payload_words; ++word_idx) {
        g_shadow_frame_words[GATEWAY_SHADOW_FRAME_HEADER_WORDS + word_idx] =
            gateway_shadow_payload_word(g_shadow_payload_pool[payload_slot_idx], word_idx);
    }

    *frame_word_count_out = frame_word_count;
    return 0;
}

static int gateway_shadow_inject_frame(uint16_t frame_word_count)
{
    uint32_t word_idx;

    gateway_shadow_wrap_write32(WRAP_REG_INJ_CTRL, GATEWAY_SHADOW_INJ_ARM_CTRL);
    DATA_SYNC;
    usleep(1000U);
    gateway_shadow_wrap_write32(WRAP_REG_INJ_CTRL, (frame_word_count << 16));
    for (word_idx = 0U; word_idx < frame_word_count; ++word_idx) {
        gateway_shadow_wrap_write32(WRAP_REG_INJ_DATA, g_shadow_frame_words[word_idx]);
    }
    DATA_SYNC;
    return 0;
}

static int gateway_shadow_start_next_job(void)
{
    gateway_shadow_job_t *job;
    uint8_t slot_idx;
    uint32_t frame_word_count = 0U;
    int rc;

    if ((g_shadow_run_state == GATEWAY_SHADOW_RUN_HALTED) ||
        (g_shadow_run_state == GATEWAY_SHADOW_RUN_DISABLED) ||
        (g_shadow_active_slot_valid != 0U) ||
        (g_shadow_pending_count == 0U)) {
        return 0;
    }

    slot_idx = g_shadow_pending_slots[g_shadow_pending_head];
    g_shadow_pending_head = (uint8_t)((g_shadow_pending_head + 1U) % GATEWAY_SHADOW_QUEUE_DEPTH);
    g_shadow_pending_count--;

    job = &g_shadow_queue[slot_idx];
    job->state = GATEWAY_SHADOW_JOB_ACTIVE;
    job->payload_slot_idx = slot_idx;
    job->status = 0U;
    job->dma_status = 0U;
    job->csw = 0U;
    job->actual_len = 0U;
    job->frame_word_count = 0U;
    job->ring_hw_head = 0U;
    job->ring_sw_tail = 0U;
    rc = gateway_shadow_build_frame(slot_idx,
                                    job->local_port,
                                    job->remote_ip,
                                    job->remote_port,
                                    job->payload_len,
                                    &frame_word_count);
    if (rc != 0) {
        g_shadow_stats.submit_fail++;
        xil_printf("udp_crypto_gateway: shadow frame build rc=%d slot=%u local_port=%u len=%u\r\n",
                   rc,
                   (unsigned)slot_idx,
                   (unsigned)job->local_port,
                   (unsigned)job->payload_len);
        job->state = GATEWAY_SHADOW_JOB_FAILED;
        gateway_shadow_release_slot(slot_idx);
        g_shadow_run_state = GATEWAY_SHADOW_RUN_READY;
        return -1;
    }
    job->frame_word_count = (uint16_t)frame_word_count;
    gateway_shadow_wrap_write32(WRAP_REG_TXCAP_CTRL, 1U);
    DATA_SYNC;
    job->acl_count_base = gateway_shadow_wrap_read32(WRAP_REG_ACL_CNT);
    job->fastpath_hit_count_base = gateway_shadow_wrap_read32(WRAP_REG_FASTPATH_HIT_COUNT);
    job->fastpath_fallback_count_base = gateway_shadow_wrap_read32(WRAP_REG_FASTPATH_FALLBACK_COUNT);

    gateway_shadow_prepare_ring();
    rc = dma_ring_submit_stream(&g_shadow_ring_ctx,
                                (uint32_t)(uintptr_t)g_shadow_dma_region.words,
                                gateway_shadow_buffer_capacity(job->expected_actual_len),
                                0,
                                0);
    if (rc != 0) {
        g_shadow_stats.submit_fail++;
        xil_printf("udp_crypto_gateway: shadow submit rc=%d slot=%u local_port=%u len=%u sw_tail=%u\r\n",
                   rc,
                   (unsigned)slot_idx,
                   (unsigned)job->local_port,
                   (unsigned)job->payload_len,
                   GATEWAY_UART_U32(g_shadow_ring_ctx.sw_tail));
        job->state = GATEWAY_SHADOW_JOB_FAILED;
        gateway_shadow_release_slot(slot_idx);
        g_shadow_run_state = GATEWAY_SHADOW_RUN_READY;
        return -2;
    }

    rc = gateway_shadow_inject_frame(job->frame_word_count);
    if (rc != 0) {
        g_shadow_stats.submit_fail++;
        xil_printf("udp_crypto_gateway: shadow inject rc=%d slot=%u local_port=%u len=%u\r\n",
                   rc,
                   (unsigned)slot_idx,
                   (unsigned)job->local_port,
                   (unsigned)job->payload_len);
        job->state = GATEWAY_SHADOW_JOB_FAILED;
        gateway_shadow_release_slot(slot_idx);
        g_shadow_run_state = GATEWAY_SHADOW_RUN_READY;
        return -3;
    }

    g_shadow_active_slot_idx = slot_idx;
    g_shadow_active_slot_valid = 1U;
    g_shadow_run_state = GATEWAY_SHADOW_RUN_ACTIVE;
    xil_printf("udp_crypto_gateway: shadow active algo=%s local_port=%u len=%u slot=%u sw_tail=%u\r\n",
               gateway_algo_name(job->algo),
               (unsigned)job->local_port,
               (unsigned)job->payload_len,
               (unsigned)slot_idx,
               GATEWAY_UART_U32(g_shadow_ring_ctx.sw_tail));
    return 0;
}

static int gateway_shadow_poll_active_job(uint32_t *csw_out)
{
    uint32_t poll_idx;
    volatile dma_ring_desc_t *desc = &g_shadow_desc_region.ring[0];

    for (poll_idx = 0U; poll_idx < GATEWAY_SHADOW_POLL_TIMEOUT; ++poll_idx) {
        uint32_t csw;

        Xil_DCacheInvalidateRange((INTPTR)desc, sizeof(*desc));
        DATA_SYNC;
        csw = desc->csw;
        if (((csw & DMA_DESC_CSW_OWNER) == 0U) && ((csw & DMA_DESC_CSW_DONE) != 0U)) {
            *csw_out = csw;
            return 0;
        }
    }

    return -1;
}

static void gateway_shadow_halt_on_timeout(uint8_t slot_idx)
{
    gateway_shadow_job_t *job = &g_shadow_queue[slot_idx];
    volatile dma_ring_desc_t *desc = &g_shadow_desc_region.ring[0];

    Xil_DCacheInvalidateRange((INTPTR)desc, sizeof(*desc));
    DATA_SYNC;
    g_shadow_last_timeout_slot = slot_idx;
    g_shadow_last_timeout_status = Xil_In32((UINTPTR)(g_shadow_ring_ctx.csr_base + DMA_CSR_STATUS));
    g_shadow_last_timeout_actual_len = desc->actual_len;
    g_shadow_last_timeout_csw = desc->csw;
    g_shadow_last_timeout_hw_head = dma_ring_get_hw_head(&g_shadow_ring_ctx);
    g_shadow_last_timeout_sw_tail = g_shadow_ring_ctx.sw_tail;

    job->status = g_shadow_last_timeout_csw;
    job->dma_status = g_shadow_last_timeout_status;
    job->csw = g_shadow_last_timeout_csw;
    job->actual_len = (uint16_t)g_shadow_last_timeout_actual_len;
    job->ring_hw_head = (uint16_t)g_shadow_last_timeout_hw_head;
    job->ring_sw_tail = (uint16_t)g_shadow_last_timeout_sw_tail;
    job->state = GATEWAY_SHADOW_JOB_FAILED;

    g_shadow_stats.poll_timeout++;
    g_shadow_stats.timeout_halt_count++;
    g_shadow_halt_reason = GATEWAY_SHADOW_HALT_REASON_POLL_TIMEOUT;
    g_shadow_run_state = GATEWAY_SHADOW_RUN_HALTED;
    g_shadow_active_slot_valid = 0U;
    xil_printf("SHADOW_TIMEOUT_HALT PASS slot=%u status=0x%08x actual_len=%u hw_head=%u sw_tail=%u\r\n",
               (unsigned)slot_idx,
               GATEWAY_UART_U32(g_shadow_last_timeout_status),
               GATEWAY_UART_U32(g_shadow_last_timeout_actual_len),
               GATEWAY_UART_U32(g_shadow_last_timeout_hw_head),
               GATEWAY_UART_U32(g_shadow_last_timeout_sw_tail));
    gateway_shadow_release_slot(slot_idx);
}
#else
static uint16_t gateway_shadow_acl_hash_tuple(uint32_t src_ip,
                                              uint16_t src_port,
                                              uint32_t dst_ip,
                                              uint16_t dst_port,
                                              uint8_t protocol)
{
    (void)src_ip;
    (void)src_port;
    (void)dst_ip;
    (void)dst_port;
    (void)protocol;
    return 0U;
}

static void gateway_shadow_acl_pack_rule_regs(uint32_t src_ip,
                                              uint16_t src_port,
                                              uint32_t dst_ip,
                                              uint16_t dst_port,
                                              uint8_t protocol,
                                              uint32_t *data0_out,
                                              uint32_t *data1_out,
                                              uint32_t *data2_out,
                                              uint32_t *data3_out)
{
    (void)src_ip;
    (void)src_port;
    (void)dst_ip;
    (void)dst_port;
    (void)protocol;
    *data0_out = 0U;
    *data1_out = 0U;
    *data2_out = 0U;
    *data3_out = 0U;
}

static int gateway_shadow_acl_write_rule(uint32_t src_ip,
                                         uint16_t src_port,
                                         uint32_t dst_ip,
                                         uint16_t dst_port,
                                         uint8_t protocol)
{
    (void)src_ip;
    (void)src_port;
    (void)dst_ip;
    (void)dst_port;
    (void)protocol;
    return -1;
}

static void gateway_shadow_acl_clear_all(void)
{
}
#endif

static int gateway_shadow_submit_live_mirror(gateway_algo_t algo,
                                             uint16_t local_port,
                                             const ip_addr_t *remote_ip,
                                             uint16_t remote_port,
                                             const uint8_t *payload_src,
                                             uint16_t payload_len)
{
#if UDP_GATEWAY_ENABLE_SHADOW_MIRROR
    gateway_shadow_job_t *job;
    uint8_t payload_slot_idx;

    if (g_shadow_run_state == GATEWAY_SHADOW_RUN_DISABLED) {
        return 1;
    }
    if (g_shadow_run_state == GATEWAY_SHADOW_RUN_HALTED) {
        g_shadow_stats.skip_busy++;
        g_shadow_stats.skipped_halted++;
        return 1;
    }
    if ((remote_ip == NULL) || (payload_src == NULL) ||
        (payload_len == 0U) || (payload_len > GATEWAY_MAX_PAYLOAD_BYTES)) {
        return -1;
    }
    if (g_shadow_pending_count >= GATEWAY_SHADOW_QUEUE_DEPTH) {
        g_shadow_stats.skip_busy++;
        return 1;
    }
    if (gateway_shadow_allocate_slot(&payload_slot_idx) != 0) {
        g_shadow_stats.skip_busy++;
        return 1;
    }

    memcpy(g_shadow_payload_pool[payload_slot_idx], payload_src, payload_len);

    job = &g_shadow_queue[payload_slot_idx];
    memset(job, 0, sizeof(*job));
    job->algo = algo;
    job->local_port = local_port;
    job->remote_ip = lwip_ntohl(ip4_addr_get_u32(ip_2_ip4(remote_ip)));
    job->remote_port = remote_port;
    job->payload_len = payload_len;
    job->expected_actual_len = payload_len;
    job->payload_slot_idx = payload_slot_idx;
    job->state = GATEWAY_SHADOW_JOB_QUEUED;

    g_shadow_pending_slots[g_shadow_pending_tail] = payload_slot_idx;
    g_shadow_pending_tail = (uint8_t)((g_shadow_pending_tail + 1U) % GATEWAY_SHADOW_QUEUE_DEPTH);
    g_shadow_pending_count++;
    g_shadow_stats.accepted++;
    xil_printf("udp_crypto_gateway: shadow queued algo=%s local_port=%u len=%u slot=%u pending=%u\r\n",
               gateway_algo_name(algo),
               (unsigned)local_port,
               (unsigned)payload_len,
               (unsigned)payload_slot_idx,
               (unsigned)g_shadow_pending_count);
    return 0;
#else
    (void)algo;
    (void)local_port;
    (void)remote_ip;
    (void)remote_port;
    (void)payload_src;
    (void)payload_len;
    return 1;
#endif
}

static int gateway_shadow_compare_result(uint8_t payload_slot_idx,
                                         uint16_t payload_len,
                                         uint16_t expected_actual_len,
                                         uint32_t csw,
                                         uint16_t actual_len)
{
#if UDP_GATEWAY_ENABLE_SHADOW_MIRROR
    uint32_t word_idx;
    uint32_t payload_words;
    uint32_t invalidate_len;

    if (payload_slot_idx >= GATEWAY_SHADOW_QUEUE_DEPTH) {
        return -1;
    }
    if (((csw & DMA_DESC_CSW_ERR) != 0U) || ((csw & DMA_DESC_CSW_STS_MASK) != DMA_DESC_CSW_STS_OK)) {
        return -2;
    }
    invalidate_len = gateway_shadow_buffer_capacity(expected_actual_len);
    if ((actual_len < payload_len) || (actual_len > invalidate_len)) {
        return -3;
    }
    dma_ring_invalidate_result(g_shadow_dma_region.words, invalidate_len);
    payload_words = payload_len / GATEWAY_SHADOW_WORD_BYTES;
    for (word_idx = 0U; word_idx < payload_words; ++word_idx) {
        uint32_t actual_word = g_shadow_dma_region.words[word_idx];
        uint32_t expected_word =
            gateway_shadow_payload_word(g_shadow_payload_pool[payload_slot_idx], word_idx);

        if (actual_word != expected_word) {
            xil_printf("udp_crypto_gateway: shadow compare word mismatch idx=%u got=0x%08x exp=0x%08x\r\n",
                       GATEWAY_UART_U32(word_idx),
                       GATEWAY_UART_U32(actual_word),
                       GATEWAY_UART_U32(expected_word));
            return -4;
        }
    }
    return 0;
#else
    (void)payload_slot_idx;
    (void)payload_len;
    (void)expected_actual_len;
    (void)csw;
    (void)actual_len;
    return 0;
#endif
}

static int gateway_shadow_compare_fastpath_result(uint8_t payload_slot_idx,
                                                  uint16_t frame_word_count)
{
#if UDP_GATEWAY_ENABLE_SHADOW_MIRROR
    uint32_t txcap_status;
    uint32_t word_idx;
    uint32_t txcap_word_count;

    if (payload_slot_idx >= GATEWAY_SHADOW_QUEUE_DEPTH) {
        return -1;
    }

    txcap_status = gateway_shadow_wrap_read32(WRAP_REG_TXCAP_STATUS);
    if ((txcap_status & 0x00010000U) == 0U) {
        return -2;
    }
    txcap_word_count = txcap_status & 0x000003FFU;
    if (txcap_word_count != frame_word_count) {
        return -3;
    }

    for (word_idx = 0U; word_idx < frame_word_count; ++word_idx) {
        uint32_t actual_word = gateway_shadow_wrap_read32(WRAP_REG_TXCAP_DATA);
        uint32_t expected_word = g_shadow_frame_words[word_idx];

        if (actual_word != expected_word) {
            xil_printf("udp_crypto_gateway: shadow fastpath word mismatch idx=%u got=0x%08x exp=0x%08x\r\n",
                       GATEWAY_UART_U32(word_idx),
                       GATEWAY_UART_U32(actual_word),
                       GATEWAY_UART_U32(expected_word));
            gateway_shadow_wrap_write32(WRAP_REG_TXCAP_CTRL, 1U);
            DATA_SYNC;
            return -4;
        }

        if ((word_idx + 1U) != frame_word_count) {
            gateway_shadow_wrap_write32(WRAP_REG_TXCAP_CTRL, 2U);
            DATA_SYNC;
        }
    }

    gateway_shadow_wrap_write32(WRAP_REG_TXCAP_CTRL, 1U);
    DATA_SYNC;
    return 0;
#else
    (void)payload_slot_idx;
    (void)payload_len;
    return 0;
#endif
}

static void gateway_shadow_service(void)
{
#if UDP_GATEWAY_ENABLE_SHADOW_MIRROR
    if (g_shadow_run_state == GATEWAY_SHADOW_RUN_HALTED) {
        if ((GATEWAY_SHADOW_HALT_LOG_ONCE != 0U) && (g_shadow_halt_logged == 0U)) {
            xil_printf("udp_crypto_gateway: shadow halted reason=%u slot=%u dma_status=0x%08x csw=0x%08x actual_len=%u hw_head=%u sw_tail=%u\r\n",
                       (unsigned)g_shadow_halt_reason,
                       GATEWAY_UART_U32(g_shadow_last_timeout_slot),
                       GATEWAY_UART_U32(g_shadow_last_timeout_status),
                       GATEWAY_UART_U32(g_shadow_last_timeout_csw),
                       GATEWAY_UART_U32(g_shadow_last_timeout_actual_len),
                       GATEWAY_UART_U32(g_shadow_last_timeout_hw_head),
                       GATEWAY_UART_U32(g_shadow_last_timeout_sw_tail));
            g_shadow_halt_logged = 1U;
        }
        return;
    }

    if (g_shadow_active_slot_valid == 0U) {
        (void)gateway_shadow_start_next_job();
        return;
    }

    {
        gateway_shadow_job_t *job = &g_shadow_queue[g_shadow_active_slot_idx];
        uint32_t csw = 0U;
        uint32_t acl_count = gateway_shadow_wrap_read32(WRAP_REG_ACL_CNT);
        uint32_t fastpath_hit_count = gateway_shadow_wrap_read32(WRAP_REG_FASTPATH_HIT_COUNT);
        uint32_t fastpath_fallback_count = gateway_shadow_wrap_read32(WRAP_REG_FASTPATH_FALLBACK_COUNT);
        uint32_t fastpath_reason = 0U;

        if (fastpath_hit_count != job->fastpath_hit_count_base) {
            uint32_t txcap_status = gateway_shadow_wrap_read32(WRAP_REG_TXCAP_STATUS);

            job->status = gateway_shadow_wrap_read32(WRAP_REG_FASTPATH_STATUS);
            job->dma_status = 0U;
            job->actual_len = job->payload_len;
            job->ring_hw_head = 0U;
            job->ring_sw_tail = g_shadow_ring_ctx.sw_tail;

            if (gateway_shadow_compare_fastpath_result(g_shadow_active_slot_idx,
                                                       job->frame_word_count) != 0) {
                g_shadow_stats.compare_fail++;
                xil_printf("udp_crypto_gateway: shadow fastpath compare fail algo=%s local_port=%u status=0x%08x\r\n",
                           gateway_algo_name(job->algo),
                           (unsigned)job->local_port,
                           GATEWAY_UART_U32(job->status));
            } else {
                g_shadow_stats.pass++;
                xil_printf("SHADOW_FASTPATH PASS actual_len=%u\r\n",
                           (unsigned)job->actual_len);
                xil_printf("FASTPATH_HIT_COUNT count=%u\r\n",
                           GATEWAY_UART_U32(fastpath_hit_count));
                xil_printf("FASTPATH_FALLBACK_COUNT count=%u\r\n",
                           GATEWAY_UART_U32(fastpath_fallback_count));
                xil_printf("TXCAP words=%u frame_words=%u status=0x%08x\r\n",
                           GATEWAY_UART_U32(txcap_status & 0x000003FFU),
                           (unsigned)job->frame_word_count,
                           GATEWAY_UART_U32(job->status));
                if (job->algo == GATEWAY_ALGO_AES) {
                    xil_printf("SHADOW_AES PASS actual_len=%u\r\n",
                               (unsigned)job->actual_len);
                    gateway_shadow_mark_milestone(GATEWAY_SHADOW_MILESTONE_SHADOW_AES);
                } else {
                    xil_printf("SHADOW_SM4 PASS actual_len=%u\r\n",
                               (unsigned)job->actual_len);
                    gateway_shadow_mark_milestone(GATEWAY_SHADOW_MILESTONE_SHADOW_SM4);
                }
            }

            gateway_shadow_prepare_ring();
            job->state = GATEWAY_SHADOW_JOB_DONE;
            gateway_shadow_release_slot(g_shadow_active_slot_idx);
            g_shadow_active_slot_valid = 0U;
            g_shadow_run_state = GATEWAY_SHADOW_RUN_READY;
            return;
        }

        if (fastpath_fallback_count != job->fastpath_fallback_count_base) {
            job->fastpath_fallback_count_base = fastpath_fallback_count;
            job->status = gateway_shadow_wrap_read32(WRAP_REG_FASTPATH_STATUS);
            fastpath_reason = (job->status >> GATEWAY_FASTPATH_STATUS_REASON_SHIFT) &
                              GATEWAY_FASTPATH_STATUS_REASON_MASK;
            xil_printf("SHADOW_FASTPATH FALLBACK status=0x%08x local_port=%u len=%u\r\n",
                       GATEWAY_UART_U32(job->status),
                       (unsigned)job->local_port,
                       (unsigned)job->payload_len);
            xil_printf("FASTPATH_FALLBACK_COUNT count=%u\r\n",
                       GATEWAY_UART_U32(fastpath_fallback_count));

            /* ACL-dropped mirror frames terminate in the wrapper. They should not
             * fall through into the descriptor-based compare path. */
            if (fastpath_reason == GATEWAY_FASTPATH_REASON_ACL_DROP) {
                g_last_drop_reason = GATEWAY_DROP_REASON_ACL;
                g_diag_acl_hit_seen = 1U;
                xil_printf("SHADOW_ACL_DROP PASS status=0x%08x local_port=%u len=%u\r\n",
                           GATEWAY_UART_U32(job->status),
                           (unsigned)job->local_port,
                           (unsigned)job->payload_len);
                gateway_shadow_prepare_ring();
                job->state = GATEWAY_SHADOW_JOB_DONE;
                gateway_shadow_release_slot(g_shadow_active_slot_idx);
                g_shadow_active_slot_valid = 0U;
                g_shadow_run_state = GATEWAY_SHADOW_RUN_READY;
                return;
            }
        }

        if (acl_count != job->acl_count_base) {
            job->acl_count_base = acl_count;
            job->status = gateway_shadow_wrap_read32(WRAP_REG_FASTPATH_STATUS);
            g_last_drop_reason = GATEWAY_DROP_REASON_ACL;
            g_diag_acl_hit_seen = 1U;
            xil_printf("SHADOW_ACL_DROP PASS acl_count=%u local_port=%u len=%u\r\n",
                       GATEWAY_UART_U32(acl_count),
                       (unsigned)job->local_port,
                       (unsigned)job->payload_len);
            gateway_shadow_prepare_ring();
            job->state = GATEWAY_SHADOW_JOB_DONE;
            gateway_shadow_release_slot(g_shadow_active_slot_idx);
            g_shadow_active_slot_valid = 0U;
            g_shadow_run_state = GATEWAY_SHADOW_RUN_READY;
            return;
        }

        if (gateway_shadow_poll_active_job(&csw) != 0) {
            gateway_shadow_halt_on_timeout(g_shadow_active_slot_idx);
            return;
        }

        job->csw = csw;
        job->status = csw;
        job->dma_status = Xil_In32((UINTPTR)(g_shadow_ring_ctx.csr_base + DMA_CSR_STATUS));
        job->actual_len = (uint16_t)dma_ring_read_actual_len(&g_shadow_desc_region.ring[0]);
        job->ring_hw_head = dma_ring_get_hw_head(&g_shadow_ring_ctx);
        job->ring_sw_tail = g_shadow_ring_ctx.sw_tail;

        if (gateway_shadow_compare_result(g_shadow_active_slot_idx,
                                          job->payload_len,
                                          job->expected_actual_len,
                                          csw,
                                          job->actual_len) != 0) {
            g_shadow_stats.compare_fail++;
            xil_printf("udp_crypto_gateway: shadow compare fail algo=%s local_port=%u actual_len=%u csw=0x%08x\r\n",
                       gateway_algo_name(job->algo),
                       (unsigned)job->local_port,
                       (unsigned)job->actual_len,
                       GATEWAY_UART_U32(csw));
        } else {
            g_shadow_stats.pass++;
            if (job->algo == GATEWAY_ALGO_AES) {
                xil_printf("SHADOW_AES PASS actual_len=%u\r\n",
                           (unsigned)job->actual_len);
                gateway_shadow_mark_milestone(GATEWAY_SHADOW_MILESTONE_SHADOW_AES);
            } else {
                xil_printf("SHADOW_SM4 PASS actual_len=%u\r\n",
                           (unsigned)job->actual_len);
                gateway_shadow_mark_milestone(GATEWAY_SHADOW_MILESTONE_SHADOW_SM4);
            }
        }

        job->state = GATEWAY_SHADOW_JOB_DONE;
        gateway_shadow_release_slot(g_shadow_active_slot_idx);
        g_shadow_active_slot_valid = 0U;
        g_shadow_run_state = GATEWAY_SHADOW_RUN_READY;
    }
#endif
}

#if !UDP_GATEWAY_ENABLE_SHADOW_MIRROR
static inline uint32_t gateway_wrap_read32(uint32_t offset)
{
    return Xil_In32((UINTPTR)(WRAPPER_BASE_ADDR + offset));
}
#endif

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
        xil_printf("udp_crypto_gateway: IO PLL relock timeout status=0x%08x\r\n",
                   GATEWAY_UART_U32(Xil_In32(IO_PLL_STATUS_ADDR)));
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
        WRAP_REG_NET_APPLIED_MAC_HI,
        WRAP_REG_FASTPATH_STATUS,
        WRAP_REG_FASTPATH_HIT_COUNT,
        WRAP_REG_FASTPATH_FALLBACK_COUNT
    };

    /* ===== SLCR PL registers (PS-side: clock/reset/level-shifter) ===== */
    xil_printf("\r\n===== SLCR PL Diagnostics =====\r\n");

    val = Xil_In32(IO_PLL_CTRL_ADDR);
    xil_printf("IO_PLL_CTRL     (0xF8000108) = 0x%08x\r\n", GATEWAY_UART_U32(val));

    val = Xil_In32(IO_PLL_STATUS_ADDR);
    xil_printf("IO_PLL_STATUS   (0xF800010C) = 0x%08x\r\n", GATEWAY_UART_U32(val));

    val = Xil_In32(IO_PLL_CFG_ADDR);
    xil_printf("IO_PLL_CFG      (0xF8000118) = 0x%08x\r\n", GATEWAY_UART_U32(val));

    val = Xil_In32(GEM0_RCLK_CTRL_ADDR);
    xil_printf("GEM0_RCLK_CTRL  (0xF8000138) = 0x%08x\r\n", GATEWAY_UART_U32(val));

    val = Xil_In32(GEM0_CLK_CTRL_ADDR);
    xil_printf("GEM0_CLK_CTRL   (0xF8000140) = 0x%08x\r\n", GATEWAY_UART_U32(val));

    val = Xil_In32(TRACE_CLK_CTRL_ADDR);
    xil_printf("TRACE_CLK_CTRL  (0xF8000168) = 0x%08x\r\n", GATEWAY_UART_U32(val));

    val = Xil_In32(0xF8000170U);
    xil_printf("FPGA0_CLK_CTRL  (0xF8000170) = 0x%08x\r\n", GATEWAY_UART_U32(val));

    val = Xil_In32(0xF80001C4U);
    xil_printf("FPGA_CLK621     (0xF80001C4) = 0x%08x\r\n", GATEWAY_UART_U32(val));

    val = Xil_In32(0xF8000240U);
    xil_printf("FPGA_RST_CTRL   (0xF8000240) = 0x%08x\r\n", GATEWAY_UART_U32(val));

    val = Xil_In32(0xF8000900U);
    xil_printf("LVL_SHIFTERS_EN (0xF8000900) = 0x%08x\r\n", GATEWAY_UART_U32(val));

    /* DEVCFG STATUS: bit2 = PCFG_DONE (PL configured?) */
    val = Xil_In32(0xF8007014U);
    xil_printf("DEVCFG_STATUS   (0xF8007014) = 0x%08x\r\n", GATEWAY_UART_U32(val));
    xil_printf("  PCFG_DONE = %u\r\n", (unsigned)((val >> 2) & 1U));

    xil_printf("\r\n===== Active MMIO Bases =====\r\n");
    xil_printf("CRYPTO_BASE_ADDR  = 0x%08x", GATEWAY_UART_ADDR(CRYPTO_BASE_ADDR));
#ifdef CRYPTO_BASE_FALLBACK
    xil_printf(" (fallback)");
#endif
    xil_printf("\r\n");
    xil_printf("WRAPPER_BASE_ADDR = 0x%08x", GATEWAY_UART_ADDR(WRAPPER_BASE_ADDR));
#ifdef WRAPPER_BASE_FALLBACK
    xil_printf(" (fallback)");
#endif
    xil_printf("\r\n");

    /* ===== Crypto IP raw dump: 0x43C00000 ~ 0x43C0003C ===== */
    xil_printf("\r\n===== Crypto MMIO Raw Dump (0x%08x) =====\r\n",
               GATEWAY_UART_ADDR(CRYPTO_BASE_ADDR));
    for (i = 0; i < 16; ++i) {
        uint32_t addr = CRYPTO_BASE_ADDR + (uint32_t)(i * 4);
        val = Xil_In32(addr);
        xil_printf("  [0x%08x] = 0x%08x\r\n", GATEWAY_UART_U32(addr), GATEWAY_UART_U32(val));
    }

    /* ===== Wrapper probe: read non-zero-default and applied-status CSRs ===== */
    xil_printf("\r\n===== Wrapper CSR Probe (0x%08x) =====\r\n",
               GATEWAY_UART_ADDR(WRAPPER_BASE_ADDR));
    for (i = 0; i < (int)(sizeof(wrapper_probe_offsets) / sizeof(wrapper_probe_offsets[0])); ++i) {
        uint32_t addr = WRAPPER_BASE_ADDR + wrapper_probe_offsets[i];
        val = Xil_In32(addr);
        xil_printf("  [0x%08x] = 0x%08x\r\n", GATEWAY_UART_U32(addr), GATEWAY_UART_U32(val));
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
static uint32_t gateway_now_ms32(void);
static void gateway_refresh_session_activity(gateway_session_t *session);
static void gateway_timeout_invalidate_session(gateway_session_t *session);
static void gateway_session_expire_if_idle(gateway_session_t *session);

static void gateway_load_key_to_hw(const gateway_request_t *job)
{
    const uint32_t *key_offsets = (job->algo == GATEWAY_ALGO_SM4) ? g_gateway_sm4_key_offsets : g_gateway_aes_key_offsets;
    uint32_t i;
    int verbose = gateway_log_block_details(job);

    for (i = 0U; i < 4U; ++i) {
        uint32_t key_word = gateway_load_be_word(&job->effective_key[i * 4U]);
        if (verbose || (i == 0U)) {
            xil_printf("udp_crypto_gateway: load_key algo=%s[%u] off=0x%02x val=0x%08x\r\n",
                       gateway_algo_name(job->algo),
                       GATEWAY_UART_U32(i),
                       GATEWAY_UART_U32(key_offsets[i]),
                       GATEWAY_UART_U32(key_word));
        }
        gateway_backend_write_key_word(key_offsets[i], key_word);
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
    xil_printf("%s0x%08x\r\n", label, GATEWAY_UART_U32(value));
}

static void smoke_print_word_vector(const char *label, const uint32_t *words, uint32_t word_count)
{
    uint32_t i;

    for (i = 0U; i < word_count; ++i) {
        xil_printf("%s[%u] = 0x%08x\r\n",
                   label,
                   GATEWAY_UART_U32(i),
                   GATEWAY_UART_U32(words[i]));
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

static uint64_t gateway_get_device_dna_raw(void)
{
    uint32_t status = gateway_wrap_read32(WRAP_REG_DEVICE_DNA_STATUS);

    if ((status & GATEWAY_DEVICE_DNA_STATUS_VALID) != 0U) {
        uint32_t dna_lo = gateway_wrap_read32(WRAP_REG_DEVICE_DNA_LO);
        uint32_t dna_hi = gateway_wrap_read32(WRAP_REG_DEVICE_DNA_HI);
        return (((uint64_t)dna_hi << 32) | (uint64_t)dna_lo);
    }

    return GATEWAY_DEVICE_DNA_FALLBACK;
}

static uint32_t gateway_fold_device_binding_id(uint64_t device_dna)
{
    uint8_t material[8];
    uint32_t dna_hi = (uint32_t)(device_dna >> 32);
    uint32_t dna_lo = (uint32_t)(device_dna & 0xFFFFFFFFU);

    gateway_store_be_word(&material[0], dna_hi);
    gateway_store_be_word(&material[4], dna_lo);
    return gateway_fnv1a32_bytes(material, sizeof(material), 0x811C9DC5U ^ GATEWAY_BINDING_ID_DEFAULT);
}

static uint32_t gateway_get_device_binding_id(void)
{
    return gateway_fold_device_binding_id(gateway_get_device_dna_raw());
}

static void gateway_derive_effective_key(const uint8_t *user_key, uint64_t device_dna, gateway_algo_t algo, uint8_t *out_key)
{
    uint8_t material[26];
    uint32_t dna_hi = (uint32_t)(device_dna >> 32);
    uint32_t dna_lo = (uint32_t)(device_dna & 0xFFFFFFFFU);
    uint32_t counter;

    memcpy(material, user_key, 16U);
    gateway_store_be_word(&material[16], dna_hi);
    gateway_store_be_word(&material[20], dna_lo);
    material[24] = (uint8_t)algo;

    for (counter = 0U; counter < 4U; ++counter) {
        uint32_t word;

        material[25] = (uint8_t)counter;
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

    if (remote_ip == NULL) {
        return NULL;
    }

    for (i = 0U; i < GATEWAY_MAX_SESSIONS; ++i) {
        if (g_sessions[i].active != 0U) {
            gateway_session_expire_if_idle(&g_sessions[i]);
        }
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
        session->device_dna = gateway_get_device_dna_raw();
        session->binding_id = gateway_fold_device_binding_id(session->device_dna);
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
            g_sessions[i].device_dna = gateway_get_device_dna_raw();
            g_sessions[i].binding_id = gateway_fold_device_binding_id(g_sessions[i].device_dna);
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

static void gateway_hw_sync_cache_invalidate(void)
{
    memset(&g_hw_sync_cache, 0, sizeof(g_hw_sync_cache));
}

static uint32_t gateway_now_ms32(void)
{
    XTime now_ticks;
    uint64_t now_ms;

    XTime_GetTime(&now_ticks);
    now_ms = ((uint64_t)now_ticks * 1000ULL) / (uint64_t)COUNTS_PER_SECOND;
    return (uint32_t)now_ms;
}

static void gateway_refresh_session_activity(gateway_session_t *session)
{
    if (session == NULL) {
        return;
    }

    session->last_active_ms = gateway_now_ms32();
}

static void gateway_timeout_invalidate_session(gateway_session_t *session)
{
    uint8_t had_authorized = 0U;

    if (session == NULL) {
        return;
    }

    had_authorized = (session->authorized_algos != 0U) ? 1U : 0U;
    memset(session, 0, sizeof(*session));
    g_diag_timeout_seen = 1U;
    if (had_authorized != 0U) {
        g_diag_reauth_pending = 1U;
    }
    gateway_hw_sync_cache_invalidate();
}

static void gateway_session_expire_if_idle(gateway_session_t *session)
{
    uint32_t now_ms;

    if ((session == NULL) || (session->active == 0U)) {
        return;
    }

    now_ms = gateway_now_ms32();
    if ((uint32_t)(now_ms - session->last_active_ms) >= GATEWAY_SESSION_TIMEOUT_MS) {
        gateway_timeout_invalidate_session(session);
    }
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
    gateway_hw_sync_cache_invalidate();
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
    gateway_hw_sync_cache_invalidate();
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
    uint32_t authorized_mask_word = 0U;

    /* Legacy contract markers kept in source for static audits:
     * ((uint32_t)g_last_drop_reason << 8)
     * ((uint32_t)g_last_lock_reason << 12)
     */
    authorized_mask_word |= ((session != NULL) ? (uint32_t)session->authorized_algos : 0U) & 0xFFU;
    authorized_mask_word |= ((uint32_t)g_last_drop_reason & 0xFU) << 8;
    authorized_mask_word |= ((uint32_t)g_last_lock_reason & 0xFU) << 12;
    authorized_mask_word |= ((uint32_t)g_diag_acl_hit_seen & 0x1U) << 16;
    authorized_mask_word |= ((uint32_t)g_diag_replay_seen & 0x1U) << 17;
    authorized_mask_word |= ((uint32_t)g_diag_timeout_seen & 0x1U) << 18;
    authorized_mask_word |= ((uint32_t)g_diag_reauth_seen & 0x1U) << 19;
    gateway_store_be_word(&out[0], (session != NULL) ? session->binding_id : gateway_get_device_binding_id());
    gateway_store_be_word(&out[4], (session != NULL) ? session->session_id : 0U);
    gateway_store_be_word(&out[8], authorized_mask_word);
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
        status = gateway_backend_read_status();
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

static int gateway_drain_stale_output_sync(void)
{
    uint32_t drained_words = 0U;
    uint32_t status = 0U;

    while (drained_words < GATEWAY_MAX_STALE_DRAIN_WORDS) {
        status = gateway_backend_read_status();
        if ((status & STATUS_TX_EMPTY) != 0U) {
            return 0;
        }
        (void)gateway_backend_read_data_out();
        drained_words++;
    }

    status = gateway_backend_read_status();
    return ((status & STATUS_TX_EMPTY) != 0U) ? 0 : -1;
}

static void gateway_load_key_hw_sync(gateway_algo_t algo, const uint8_t *effective_key)
{
    const uint32_t *key_offsets = (algo == GATEWAY_ALGO_SM4) ? g_gateway_sm4_key_offsets : g_gateway_aes_key_offsets;
    uint32_t i;

    for (i = 0U; i < 4U; ++i) {
        gateway_backend_write_key_word(key_offsets[i], gateway_load_be_word(&effective_key[i * 4U]));
    }
}

static int sync_prepare_engine(uint32_t *status_out)
{
    uint32_t status = 0U;
    int rc = gateway_backend_require(GATEWAY_BACKEND_CAP_CRYPTO_SYNC, "encrypt_sync");

    if (rc != 0) {
        gateway_hw_sync_cache_invalidate();
        return rc;
    }

    if (gateway_wait_ready_sync(GATEWAY_WAIT_ENGINE_POLLS, &status) != 0) {
        g_stat_crypto_timeout++;
        gateway_hw_sync_cache_invalidate();
        return -1;
    }

    if (gateway_drain_stale_output_sync() != 0) {
        g_stat_crypto_fail++;
        gateway_hw_sync_cache_invalidate();
        return -1;
    }

    if (status_out != NULL) {
        *status_out = status;
    }
    return 0;
}

static int sync_ensure_key_and_ctrl(uint32_t session_id,
                                    gateway_algo_t algo,
                                    const uint8_t *effective_key)
{
    uint32_t ctrl_word;

    if (effective_key == NULL) {
        gateway_hw_sync_cache_invalidate();
        return -1;
    }

    ctrl_word = gateway_ctrl_word(algo);
    if ((g_hw_sync_cache.valid != 0U) &&
        (g_hw_sync_cache.session_id == session_id) &&
        (g_hw_sync_cache.algo == (uint8_t)algo) &&
        (g_hw_sync_cache.ctrl_word == ctrl_word) &&
        (memcmp(g_hw_sync_cache.effective_key, effective_key, sizeof(g_hw_sync_cache.effective_key)) == 0)) {
        return 0;
    }

    gateway_load_key_hw_sync(algo, effective_key);
    gateway_backend_write_ctrl(ctrl_word);

    g_hw_sync_cache.valid = 1U;
    g_hw_sync_cache.algo = (uint8_t)algo;
    g_hw_sync_cache.session_id = session_id;
    g_hw_sync_cache.ctrl_word = ctrl_word;
    memcpy(g_hw_sync_cache.effective_key, effective_key, sizeof(g_hw_sync_cache.effective_key));
    return 0;
}

static void sync_push_block(const uint8_t *input)
{
    uint32_t word_index;

    for (word_index = 0U; word_index < 4U; ++word_index) {
        gateway_backend_write_data_in(gateway_load_be_word(&input[word_index * 4U]));
    }
}

static void sync_pull_block_4words(uint8_t *out_block)
{
    uint32_t word_index;

    for (word_index = 0U; word_index < 4U; ++word_index) {
        gateway_store_be_word(&out_block[word_index * 4U], gateway_backend_read_data_out());
    }
}

static int GATEWAY_MAYBE_UNUSED gateway_hw_encrypt_buffer_sync(uint32_t session_id,
                                          gateway_algo_t algo,
                                          const uint8_t *effective_key,
                                          const uint8_t *input,
                                          uint8_t *output,
                                          uint16_t payload_len)
{
    gateway_hw_sync_diag_t diag;
    uint32_t status_reads_total = 0U;
    uint32_t enqueue_count = 0U;
    uint32_t drain_count = 0U;
    uint32_t scheduler_idle_spins = 0U;
    uint32_t scheduler_idle_spins_peak = 0U;
    uint32_t inflight_high_watermark = 0U;
    uint32_t scheduler_idle_limit =
        ((GATEWAY_WAIT_ENGINE_POLLS > GATEWAY_WAIT_BLOCK_POLLS) ? GATEWAY_WAIT_ENGINE_POLLS : GATEWAY_WAIT_BLOCK_POLLS) * 4U;
    uint32_t blocks_total;
    uint32_t blocks_sent = 0U;
    uint32_t blocks_completed = 0U;
    uint32_t blocks_inflight = 0U;
    uint32_t wready_stall_start = 0U;
    uint32_t wready_stall_end = 0U;
    uint16_t offset;
    uint32_t status = 0U;
    int rc;

    if ((effective_key == NULL) || (input == NULL) || (output == NULL) || ((payload_len % GATEWAY_BLOCK_BYTES) != 0U)) {
        return -1;
    }

    memset(&diag, 0, sizeof(diag));
    memset(&g_hw_sync_diag_last, 0, sizeof(g_hw_sync_diag_last));

    rc = sync_prepare_engine(&status);
    if (rc != 0) {
        return rc;
    }

    rc = sync_ensure_key_and_ctrl(session_id, algo, effective_key);
    if (rc != 0) {
        g_stat_crypto_fail++;
        gateway_hw_sync_cache_invalidate();
        return -1;
    }

    blocks_total = payload_len / GATEWAY_BLOCK_BYTES;
    wready_stall_start = gateway_backend_read_wready_stall_count();

    while (blocks_completed < blocks_total) {
        uint8_t made_progress = 0U;

        status = gateway_backend_read_status();
        status_reads_total++;

        if ((blocks_sent < blocks_total) &&
            (blocks_inflight < GATEWAY_SYNC_WINDOW_BLOCKS) &&
            ((status & STATUS_SYS_READY) != 0U)) {
            offset = (uint16_t)(blocks_sent * GATEWAY_BLOCK_BYTES);
            sync_push_block(&input[offset]);
            blocks_sent++;
            blocks_inflight++;
            enqueue_count++;
            if (blocks_inflight > inflight_high_watermark) {
                inflight_high_watermark = blocks_inflight;
            }
            scheduler_idle_spins = 0U;
            made_progress = 1U;
        } else if ((blocks_inflight > 0U) && ((status & STATUS_TX_EMPTY) == 0U)) {
            offset = (uint16_t)(blocks_completed * GATEWAY_BLOCK_BYTES);
            sync_pull_block_4words(&output[offset]);
            blocks_completed++;
            blocks_inflight--;
            drain_count++;
            scheduler_idle_spins = 0U;
            made_progress = 1U;
        }

        if (made_progress == 0U) {
            scheduler_idle_spins++;
            if (scheduler_idle_spins > scheduler_idle_spins_peak) {
                scheduler_idle_spins_peak = scheduler_idle_spins;
            }
            if (scheduler_idle_spins > scheduler_idle_limit) {
                g_stat_crypto_timeout++;
                gateway_hw_sync_cache_invalidate();
                (void)gateway_drain_stale_output_sync();
                wready_stall_end = gateway_backend_read_wready_stall_count();
                diag.status_reads_total = status_reads_total;
                diag.enqueue_count = enqueue_count;
                diag.drain_count = drain_count;
                diag.scheduler_idle_spins_peak = scheduler_idle_spins_peak;
                diag.inflight_high_watermark = inflight_high_watermark;
                diag.wready_stall_cnt_delta = wready_stall_end - wready_stall_start;
                g_hw_sync_diag_last = diag;
                return -1;
            }
        }
    }

    wready_stall_end = gateway_backend_read_wready_stall_count();
    diag.status_reads_total = status_reads_total;
    diag.enqueue_count = enqueue_count;
    diag.drain_count = drain_count;
    diag.scheduler_idle_spins_peak = scheduler_idle_spins_peak;
    diag.inflight_high_watermark = inflight_high_watermark;
    diag.wready_stall_cnt_delta = wready_stall_end - wready_stall_start;
    g_hw_sync_diag_last = diag;
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

#if UDP_GATEWAY_ENABLE_SHADOW_MIRROR
static inline void gateway_bench_dma_write32(uint32_t offset, uint32_t value)
{
    Xil_Out32((UINTPTR)(GATEWAY_SHADOW_DMA_BASEADDR + offset), value);
    DATA_SYNC;
}

static uint32_t gateway_bench_dma_stride(uint16_t payload_len)
{
    return ((uint32_t)payload_len + (DMA_ALIGNMENT_BYTES - 1U)) & ~(DMA_ALIGNMENT_BYTES - 1U);
}

static uint8_t *gateway_bench_dma_dst_slot_ptr(uint32_t slot_idx, uint32_t stride)
{
    return &g_bench_dma_dst_region.payload[slot_idx * stride];
}

static void gateway_bench_dma_write_key_regs(const uint8_t *effective_key)
{
    gateway_bench_dma_write32(GATEWAY_BENCH_DMA_KEY0_REG, gateway_load_be_word(&effective_key[12]));
    gateway_bench_dma_write32(GATEWAY_BENCH_DMA_KEY1_REG, gateway_load_be_word(&effective_key[8]));
    gateway_bench_dma_write32(GATEWAY_BENCH_DMA_KEY2_REG, gateway_load_be_word(&effective_key[4]));
    gateway_bench_dma_write32(GATEWAY_BENCH_DMA_KEY3_REG, gateway_load_be_word(&effective_key[0]));
    gateway_bench_dma_write32(GATEWAY_BENCH_DMA_KEY4_REG, 0U);
    gateway_bench_dma_write32(GATEWAY_BENCH_DMA_KEY5_REG, 0U);
    gateway_bench_dma_write32(GATEWAY_BENCH_DMA_KEY6_REG, 0U);
    gateway_bench_dma_write32(GATEWAY_BENCH_DMA_KEY7_REG, 0U);
}

static void gateway_bench_dma_configure_crypto_context(gateway_algo_t algo, const uint8_t *effective_key)
{
    uint32_t ctrl = DMA_CTRL_ENCRYPT;

    if (algo == GATEWAY_ALGO_SM4) {
        ctrl |= DMA_CTRL_ALGO_SM4;
    }

    gateway_bench_dma_write32(GATEWAY_BENCH_DMA_LOOPBACK_MODE_REG, 0U);
    gateway_bench_dma_write_key_regs(effective_key);
    gateway_bench_dma_write32(GATEWAY_BENCH_DMA_CTRL_REG, ctrl);
}

static void gateway_bench_dma_prepare_ring(void)
{
    gateway_shadow_prepare_mmio();
    dma_ring_init(&g_bench_dma_ring_ctx,
                  GATEWAY_SHADOW_DMA_BASEADDR,
                  &g_bench_dma_desc_region.ring[0],
                  (uint32_t)(uintptr_t)&g_bench_dma_desc_region.ring[0],
                  GATEWAY_BENCH_DMA_RING_ENTRY_COUNT);
    dma_ring_soft_reset(&g_bench_dma_ring_ctx);
    dma_ring_init(&g_bench_dma_ring_ctx,
                  GATEWAY_SHADOW_DMA_BASEADDR,
                  &g_bench_dma_desc_region.ring[0],
                  (uint32_t)(uintptr_t)&g_bench_dma_desc_region.ring[0],
                  GATEWAY_BENCH_DMA_RING_ENTRY_COUNT);
}

static int gateway_bench_dma_poll_last_desc(volatile dma_ring_desc_t *desc)
{
    uint32_t poll_count;

    for (poll_count = 0U; poll_count < GATEWAY_BENCH_DMA_POLL_TIMEOUT; ++poll_count) {
        int rc = dma_ring_poll_csw(desc, NULL);
        if (rc == 0) {
            return rc;
        }
        if (rc < 0) {
            return rc;
        }
    }

    return -1;
}

static int gateway_run_bench_dma_batch(gateway_algo_t algo,
                                       const uint8_t *effective_key,
                                       uint16_t payload_len,
                                       uint16_t repeats,
                                       uint32_t *hw_us_out)
{
    uint32_t stride;
    uint32_t idx;
    XTime hw_start;
    XTime hw_end;

    if ((effective_key == NULL) || (hw_us_out == NULL) || (repeats == 0U)) {
        xil_printf("udp_crypto_gateway: bench dma invalid args algo=%s len=%u repeats=%u key=%u hw_us=%u\r\n",
                   gateway_algo_name(algo),
                   (unsigned)payload_len,
                   (unsigned)repeats,
                   (unsigned)(effective_key != NULL),
                   (unsigned)(hw_us_out != NULL));
        return -1;
    }
    if (repeats > GATEWAY_BENCH_DMA_USABLE_RING_ENTRIES) {
        xil_printf("udp_crypto_gateway: bench dma repeats overflow algo=%s repeats=%u max=%u\r\n",
                   gateway_algo_name(algo),
                   (unsigned)repeats,
                   (unsigned)GATEWAY_BENCH_DMA_USABLE_RING_ENTRIES);
        return -2;
    }
    if ((payload_len == 0U) || (payload_len > GATEWAY_MAX_PAYLOAD_BYTES) ||
        ((payload_len & (GATEWAY_BLOCK_BYTES - 1U)) != 0U)) {
        xil_printf("udp_crypto_gateway: bench dma invalid len algo=%s len=%u\r\n",
                   gateway_algo_name(algo),
                   (unsigned)payload_len);
        return -3;
    }
    if ((g_shadow_run_state == GATEWAY_SHADOW_RUN_ACTIVE) || (g_shadow_active_slot_valid != 0U) ||
        (g_shadow_pending_count != 0U)) {
        xil_printf("udp_crypto_gateway: bench dma shadow busy algo=%s len=%u repeats=%u shadow_state=%u active=%u pending=%u\r\n",
                   gateway_algo_name(algo),
                   (unsigned)payload_len,
                   (unsigned)repeats,
                   (unsigned)g_shadow_run_state,
                   (unsigned)g_shadow_active_slot_valid,
                   (unsigned)g_shadow_pending_count);
        return -4;
    }

    stride = gateway_bench_dma_stride(payload_len);
    memcpy(g_bench_dma_src_region.payload, g_bench_input, payload_len);
    memset(&g_bench_dma_desc_region, 0, sizeof(g_bench_dma_desc_region));
    memset(g_bench_dma_dst_region.payload, 0xA5, repeats * stride);
    Xil_DCacheFlushRange((INTPTR)g_bench_dma_src_region.payload, payload_len);
    Xil_DCacheFlushRange((INTPTR)g_bench_dma_dst_region.payload, repeats * stride);

    gateway_bench_dma_prepare_ring();
    gateway_bench_dma_configure_crypto_context(algo, effective_key);

    for (idx = 0U; idx < repeats; ++idx) {
        int rc = dma_ring_submit_nodoorbell(
            &g_bench_dma_ring_ctx,
            (uint32_t)(uintptr_t)gateway_bench_dma_dst_slot_ptr(idx, stride),
            payload_len,
            (uint8_t)algo,
            g_bench_dma_src_region.payload,
            payload_len);
        if (rc != 0) {
            xil_printf("udp_crypto_gateway: bench dma submit rc=%d algo=%s idx=%u len=%u stride=%u dst=0x%08x src=0x%08x\r\n",
                       rc,
                       gateway_algo_name(algo),
                       (unsigned)idx,
                       (unsigned)payload_len,
                       GATEWAY_UART_U32(stride),
                       GATEWAY_UART_U32((uint32_t)(uintptr_t)gateway_bench_dma_dst_slot_ptr(idx, stride)),
                       GATEWAY_UART_U32((uint32_t)(uintptr_t)g_bench_dma_src_region.payload));
            return -5;
        }
    }

    XTime_GetTime(&hw_start);
    if (dma_ring_publish_tail(&g_bench_dma_ring_ctx) != 0) {
        xil_printf("udp_crypto_gateway: bench dma publish tail failed algo=%s len=%u repeats=%u sw_tail=%u hw_head=%u\r\n",
                   gateway_algo_name(algo),
                   (unsigned)payload_len,
                   (unsigned)repeats,
                   (unsigned)g_bench_dma_ring_ctx.sw_tail,
                   (unsigned)dma_ring_get_hw_head(&g_bench_dma_ring_ctx));
        return -6;
    }
    dma_ring_ring_doorbell(&g_bench_dma_ring_ctx);
    {
        int poll_rc = gateway_bench_dma_poll_last_desc(&g_bench_dma_desc_region.ring[repeats - 1U]);
        if (poll_rc == -1) {
            xil_printf("udp_crypto_gateway: bench dma poll timeout algo=%s len=%u repeats=%u sw_tail=%u hw_head=%u irq=0x%08x dbg_status=0x%08x dbg_src=0x%08x dbg_sink=0x%08x last_csw=0x%08x last_actual=%u\r\n",
                       gateway_algo_name(algo),
                       (unsigned)payload_len,
                       (unsigned)repeats,
                       (unsigned)g_bench_dma_ring_ctx.sw_tail,
                       (unsigned)dma_ring_get_hw_head(&g_bench_dma_ring_ctx),
                       GATEWAY_UART_U32(Xil_In32((UINTPTR)(GATEWAY_SHADOW_DMA_BASEADDR + DMA_CSR_IRQ_STATUS))),
                       GATEWAY_UART_U32(Xil_In32((UINTPTR)(GATEWAY_SHADOW_DMA_BASEADDR + DMA_CSR_DEBUG_STATUS))),
                       GATEWAY_UART_U32(Xil_In32((UINTPTR)(GATEWAY_SHADOW_DMA_BASEADDR + DMA_CSR_DEBUG_SOURCE_PROGRESS))),
                       GATEWAY_UART_U32(Xil_In32((UINTPTR)(GATEWAY_SHADOW_DMA_BASEADDR + DMA_CSR_DEBUG_SINK_PROGRESS))),
                       GATEWAY_UART_U32(g_bench_dma_desc_region.ring[repeats - 1U].csw),
                       GATEWAY_UART_U32(g_bench_dma_desc_region.ring[repeats - 1U].actual_len));
            return -7;
        }
        if (poll_rc < 0) {
            xil_printf("udp_crypto_gateway: bench dma last desc err rc=%d algo=%s len=%u repeats=%u sw_tail=%u hw_head=%u irq=0x%08x dbg_status=0x%08x dbg_src=0x%08x dbg_sink=0x%08x last_csw=0x%08x last_actual=%u\r\n",
                       poll_rc,
                       gateway_algo_name(algo),
                       (unsigned)payload_len,
                       (unsigned)repeats,
                       (unsigned)g_bench_dma_ring_ctx.sw_tail,
                       (unsigned)dma_ring_get_hw_head(&g_bench_dma_ring_ctx),
                       GATEWAY_UART_U32(Xil_In32((UINTPTR)(GATEWAY_SHADOW_DMA_BASEADDR + DMA_CSR_IRQ_STATUS))),
                       GATEWAY_UART_U32(Xil_In32((UINTPTR)(GATEWAY_SHADOW_DMA_BASEADDR + DMA_CSR_DEBUG_STATUS))),
                       GATEWAY_UART_U32(Xil_In32((UINTPTR)(GATEWAY_SHADOW_DMA_BASEADDR + DMA_CSR_DEBUG_SOURCE_PROGRESS))),
                       GATEWAY_UART_U32(Xil_In32((UINTPTR)(GATEWAY_SHADOW_DMA_BASEADDR + DMA_CSR_DEBUG_SINK_PROGRESS))),
                       GATEWAY_UART_U32(g_bench_dma_desc_region.ring[repeats - 1U].csw),
                       GATEWAY_UART_U32(g_bench_dma_desc_region.ring[repeats - 1U].actual_len));
            return -7;
        }
    }
    XTime_GetTime(&hw_end);

    for (idx = 0U; idx < repeats; ++idx) {
        volatile dma_ring_desc_t *desc = &g_bench_dma_desc_region.ring[idx];
        uint8_t *slot_ptr = gateway_bench_dma_dst_slot_ptr(idx, stride);
        uint32_t actual_len = dma_ring_read_actual_len(desc);

        if (dma_ring_poll_csw(desc, NULL) != 0) {
            xil_printf("udp_crypto_gateway: bench dma csw fail algo=%s idx=%u len=%u csw=0x%08x actual=%u\r\n",
                       gateway_algo_name(algo),
                       (unsigned)idx,
                       (unsigned)payload_len,
                       GATEWAY_UART_U32(desc->csw),
                       GATEWAY_UART_U32(actual_len));
            return -8;
        }
        if (actual_len != payload_len) {
            xil_printf("udp_crypto_gateway: bench dma actual len mismatch algo=%s idx=%u got=%u exp=%u csw=0x%08x\r\n",
                       gateway_algo_name(algo),
                       (unsigned)idx,
                       GATEWAY_UART_U32(actual_len),
                       (unsigned)payload_len,
                       GATEWAY_UART_U32(desc->csw));
            return -9;
        }
        dma_ring_invalidate_result(slot_ptr, stride);
        if (memcmp(slot_ptr, g_bench_sw_output, payload_len) != 0) {
            xil_printf("udp_crypto_gateway: bench dma compare fail algo=%s idx=%u len=%u first_word_hw=0x%08x first_word_sw=0x%08x\r\n",
                       gateway_algo_name(algo),
                       (unsigned)idx,
                       (unsigned)payload_len,
                       GATEWAY_UART_U32(gateway_load_be_word(slot_ptr)),
                       GATEWAY_UART_U32(gateway_load_be_word(g_bench_sw_output)));
            return -10;
        }
    }

    memcpy(g_bench_hw_output, gateway_bench_dma_dst_slot_ptr(0U, stride), payload_len);
    *hw_us_out = gateway_ticks_to_us(hw_end - hw_start);
    return 0;
}
#endif

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

    if (gateway_backend_require(GATEWAY_BACKEND_CAP_CRYPTO_SYNC, "bench") != 0) {
        xil_printf("udp_crypto_gateway: bench backend unavailable kind=%u caps=0x%08x\r\n",
                   (unsigned)gateway_backend_kind(),
                   GATEWAY_UART_U32(gateway_backend_caps()));
        return GATEWAY_CTRL_STATUS_INTERNAL;
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
        xil_printf("udp_crypto_gateway: bench effective key missing algo=%s session=0x%08x auth=0x%02x\r\n",
                   gateway_algo_name(algo),
                   GATEWAY_UART_U32(session->session_id),
                   (unsigned)session->authorized_algos);
        return -1;
    }

    header[0] = (uint8_t)algo;
    header[1] = (uint8_t)GATEWAY_BENCH_RECORD_COUNT;
    gateway_store_be16(&header[2], repeats);
    memcpy(payload_out, header, sizeof(header));
    payload_len = GATEWAY_BENCH_HEADER_BYTES;

    /*
     * BENCH response record contract (12 bytes each):
     *   [0..1]  payload_len for one encrypt call
     *   [2..3]  reserved, kept zero for forward compatibility
     *   [4..7]  total sw_us across `repeats` calls of gateway_sw_encrypt_buffer()
     *   [8..11] total hw_us across `repeats` calls of gateway_hw_encrypt_buffer_sync()
     *
     * Host-side reporting derives per-call latency and speedup from these totals.
     */
    for (record_index = 0U; record_index < GATEWAY_BENCH_RECORD_COUNT; ++record_index) {
        uint16_t current_len = g_gateway_bench_lengths[record_index];
        uint32_t repeat_index;
        int bench_rc;
        XTime sw_start;
        XTime sw_end;
#if !UDP_GATEWAY_ENABLE_SHADOW_MIRROR
        XTime hw_start;
        XTime hw_end;
#endif
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

#if UDP_GATEWAY_ENABLE_SHADOW_MIRROR
        bench_rc = gateway_run_bench_dma_batch(algo, effective_key, current_len, repeats, &hw_us);
        if (bench_rc != 0) {
            xil_printf("udp_crypto_gateway: bench dma rc=%d algo=%s len=%u repeats=%u shadow_state=%u active=%u pending=%u\r\n",
                       bench_rc,
                       gateway_algo_name(algo),
                       (unsigned)current_len,
                       (unsigned)repeats,
                       (unsigned)g_shadow_run_state,
                       (unsigned)g_shadow_active_slot_valid,
                       (unsigned)g_shadow_pending_count);
            g_stat_crypto_fail++;
            return GATEWAY_CTRL_STATUS_INTERNAL;
        }
#else
        XTime_GetTime(&hw_start);
        for (repeat_index = 0U; repeat_index < repeats; ++repeat_index) {
            if (gateway_hw_encrypt_buffer_sync(session->session_id,
                                               algo,
                                               effective_key,
                                               g_bench_input,
                                               g_bench_hw_output,
                                               current_len) != 0) {
                g_stat_crypto_fail++;
                return GATEWAY_CTRL_STATUS_INTERNAL;
            }
        }
        XTime_GetTime(&hw_end);
        hw_us = gateway_ticks_to_us(hw_end - hw_start);
#endif

        if (memcmp(g_bench_sw_output, g_bench_hw_output, current_len) != 0) {
            xil_printf("udp_crypto_gateway: bench final compare fail algo=%s len=%u sw0=0x%08x hw0=0x%08x\r\n",
                       gateway_algo_name(algo),
                       (unsigned)current_len,
                       GATEWAY_UART_U32(gateway_load_be_word(g_bench_sw_output)),
                       GATEWAY_UART_U32(gateway_load_be_word(g_bench_hw_output)));
            g_stat_crypto_fail++;
            return GATEWAY_CTRL_STATUS_INTERNAL;
        }

        sw_us = gateway_ticks_to_us(sw_end - sw_start);

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
    xil_printf("udp_crypto_gateway: timeout phase=%s algo=%s local_port=%u status=0x%08x src=%u.%u.%u.%u:%u len=%u offset=%u pushed=%u pulled=%u sys_ready=%u tx_empty=%u failures=%u\r\n",
               phase_name,
               gateway_algo_name(g_active_job.algo),
               (unsigned)gateway_reply_local_port(&g_active_job),
               GATEWAY_UART_U32(status),
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
               GATEWAY_UART_U32(g_stat_failures));
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
        status = gateway_backend_read_status();
        if ((status & STATUS_TX_EMPTY) != 0U) {
            break;
        }

        {
            uint32_t stale_word = gateway_backend_read_data_out();
            if (verbose) {
                xil_printf("udp_crypto_gateway: stale_data_out[%u]=0x%08x status=0x%08x\r\n",
                           GATEWAY_UART_U32(drained_words),
                           GATEWAY_UART_U32(stale_word),
                           GATEWAY_UART_U32(status));
            }
        }
        drained_words++;
    }

    xil_printf("udp_crypto_gateway: stale_drain words=%u final_status=0x%08x\r\n",
               GATEWAY_UART_U32(drained_words),
               GATEWAY_UART_U32(gateway_backend_read_status()));
}

static void gateway_push_single_block(const uint8_t *in_block, uint16_t block_offset)
{
    uint32_t i;
    int verbose = gateway_log_block_details(&g_active_job);
    uint32_t base_word_index = (uint32_t)block_offset / 4U;

    for (i = 0U; i < 4U; ++i) {
        uint32_t din = gateway_load_be_word(&in_block[i * 4U]);
        if (verbose) {
            xil_printf("udp_crypto_gateway: data_in[%u]=0x%08x\r\n",
                       GATEWAY_UART_U32(base_word_index + i),
                       GATEWAY_UART_U32(din));
        }
        gateway_backend_write_data_in(din);
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
            status = gateway_backend_read_status();
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
            uint32_t dout = gateway_backend_read_data_out();
            gateway_store_be_word(&out_block[i * 4U], dout);
            if (verbose) {
                xil_printf("udp_crypto_gateway: raw_data_out[%u]=0x%08x status=0x%08x\r\n",
                           GATEWAY_UART_U32(base_word_index + i),
                           GATEWAY_UART_U32(dout),
                           GATEWAY_UART_U32(status));
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
    xil_printf("WRITE phase=%s offset=0x%08x value=0x%08x before=0x%08x\r\n",
               phase_name,
               GATEWAY_UART_U32(offset),
               GATEWAY_UART_U32(value),
               GATEWAY_UART_U32(before));
    smoke_uart_drain();
    xil_printf("SMOKE_MARK pre_write phase=%s %s:%d offset=0x%08x value=0x%08x\r\n",
               phase_name,
               __FILE__,
               __LINE__,
               GATEWAY_UART_U32(offset),
               GATEWAY_UART_U32(value));
    smoke_uart_drain();
    smoke_write32(offset, value);
    xil_printf("SMOKE_MARK post_write phase=%s %s:%d offset=0x%08x value=0x%08x\r\n",
               phase_name,
               __FILE__,
               __LINE__,
               GATEWAY_UART_U32(offset),
               GATEWAY_UART_U32(value));
    smoke_uart_drain();
    after = smoke_read32(offset);
    xil_printf("READBACK phase=%s offset=0x%08x value=0x%08x\r\n",
               phase_name,
               GATEWAY_UART_U32(offset),
               GATEWAY_UART_U32(after));
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

    xil_printf("TEST fail: timeout phase=%s status=0x%08x pushed=%u pulled=%u sys_ready=%u tx_empty=%u\r\n",
               phase_name,
               GATEWAY_UART_U32(last_status),
               GATEWAY_UART_U32(pushed_words),
               GATEWAY_UART_U32(pulled_words),
               GATEWAY_UART_U32(last_status & STATUS_SYS_READY),
               GATEWAY_UART_U32((last_status & STATUS_TX_EMPTY) != 0U));
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

        xil_printf("STALE_DATA_OUT[%u] = 0x%08x status=0x%08x\r\n",
                   GATEWAY_UART_U32(drained_words),
                   GATEWAY_UART_U32(smoke_read32(REG_DATA_OUT)),
                   GATEWAY_UART_U32(status));
        drained_words++;
    }

    xil_printf("drained_words=%u final_status=0x%08x\r\n",
               GATEWAY_UART_U32(drained_words),
               GATEWAY_UART_U32(smoke_read32(REG_STATUS)));
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
        xil_printf("AES_LOAD_KEY[%u] offset=0x%08x value=0x%08x\r\n",
                   GATEWAY_UART_U32(i),
                   GATEWAY_UART_U32(key_offsets[i]),
                   GATEWAY_UART_U32(key_words[i]));
        smoke_write32(key_offsets[i], key_words[i]);
    }

    xil_printf("AES_CTRL value=0x%08x\r\n", GATEWAY_UART_U32(SMOKE_AES_CTRL_WORD));
    smoke_uart_drain();
    xil_printf("SMOKE_MARK pre_write phase=aes_ctrl %s:%d offset=0x%08x value=0x%08x\r\n",
               __FILE__,
               __LINE__,
               GATEWAY_UART_U32(REG_CTRL),
               GATEWAY_UART_U32(SMOKE_AES_CTRL_WORD));
    smoke_uart_drain();
    smoke_write32(REG_CTRL, SMOKE_AES_CTRL_WORD);
    xil_printf("SMOKE_MARK post_write phase=aes_ctrl %s:%d offset=0x%08x value=0x%08x\r\n",
               __FILE__,
               __LINE__,
               GATEWAY_UART_U32(REG_CTRL),
               GATEWAY_UART_U32(SMOKE_AES_CTRL_WORD));
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
        xil_printf("AES_DATA_IN[%u] = 0x%08x\r\n",
                   GATEWAY_UART_U32(i),
                   GATEWAY_UART_U32(plain_words[i]));
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
        xil_printf("RAW_DATA_OUT[%u] = 0x%08x status=0x%08x\r\n",
                   GATEWAY_UART_U32(i),
                   GATEWAY_UART_U32(actual_words[i]),
                   GATEWAY_UART_U32(status));
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
    xil_printf("TEST begin: %s offset=0x%08x value0=0x%08x value1=0x%08x before=0x%08x\r\n",
               case_name,
               GATEWAY_UART_U32(offset),
               GATEWAY_UART_U32(value0),
               GATEWAY_UART_U32(value1),
               GATEWAY_UART_U32(before));
    readback0 = smoke_write_once_and_readback("flip0", offset, value0);
    readback1 = smoke_write_once_and_readback("flip1", offset, value1);
    xil_printf("TEST done: %s offset=0x%08x readback0=0x%08x readback1=0x%08x\r\n",
               case_name,
               GATEWAY_UART_U32(offset),
               GATEWAY_UART_U32(readback0),
               GATEWAY_UART_U32(readback1));
}

static void smoke_write_ctrl_safe(void)
{
    uint32_t before_status;
    uint32_t after_status;

    before_status = smoke_read32(REG_STATUS);
    xil_printf("TEST begin: write_ctrl_safe offset=0x%08x value=0x00000000 status_before=0x%08x\r\n",
               GATEWAY_UART_U32(REG_CTRL),
               GATEWAY_UART_U32(before_status));
    smoke_uart_drain();
    xil_printf("SMOKE_MARK pre_write phase=ctrl_safe %s:%d offset=0x%08x value=0x00000000\r\n",
               __FILE__,
               __LINE__,
               GATEWAY_UART_U32(REG_CTRL));
    smoke_uart_drain();
    smoke_write32(REG_CTRL, 0x00000000U);
    xil_printf("SMOKE_MARK post_write phase=ctrl_safe %s:%d offset=0x%08x value=0x00000000\r\n",
               __FILE__,
               __LINE__,
               GATEWAY_UART_U32(REG_CTRL));
    smoke_uart_drain();
    after_status = smoke_read32(REG_STATUS);
    xil_printf("STATUS after ctrl_safe = 0x%08x\r\n", GATEWAY_UART_U32(after_status));
    xil_printf("TEST done: write_ctrl_safe status_before=0x%08x status_after=0x%08x\r\n",
               GATEWAY_UART_U32(before_status),
               GATEWAY_UART_U32(after_status));
}

int udp_crypto_gateway_run_direct_smoke_checked(unsigned case_id)
{
    uint32_t initial_status;
    int rc = 0;

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
        rc = smoke_aes_block_encrypt();
        break;
    default:
        xil_printf("TEST begin: invalid_test_case\r\n");
        xil_printf("TEST done: invalid_test_case\r\n");
        rc = -1;
        break;
    }

    return rc;
}

int udp_crypto_gateway_run_backend_split_smoke_checked(void)
{
#if UDP_GATEWAY_SMOKE_ONLY_BUILD
    return 0;
#else
    gateway_backend_select_direct_mmio();
    if ((gateway_backend_kind() != GATEWAY_BACKEND_KIND_DIRECT_MMIO) ||
        !gateway_backend_supports(GATEWAY_BACKEND_CAP_CRYPTO_SYNC) ||
        gateway_backend_supports(GATEWAY_BACKEND_CAP_DMA_PROBE)) {
        return -1;
    }

    gateway_backend_select_dma_probe();
    if ((gateway_backend_kind() != GATEWAY_BACKEND_KIND_DMA_PROBE) ||
        !gateway_backend_supports(GATEWAY_BACKEND_CAP_DMA_PROBE) ||
        gateway_backend_supports(GATEWAY_BACKEND_CAP_CRYPTO_SYNC)) {
        gateway_backend_select_direct_mmio();
        return -2;
    }

    gateway_backend_select_direct_mmio();
    if ((gateway_backend_kind() != GATEWAY_BACKEND_KIND_DIRECT_MMIO) ||
        !gateway_backend_supports(GATEWAY_BACKEND_CAP_CRYPTO_SYNC) ||
        gateway_backend_supports(GATEWAY_BACKEND_CAP_DMA_PROBE)) {
        return -3;
    }

    return 0;
#endif
}

void udp_crypto_gateway_run_direct_smoke(unsigned case_id)
{
    (void)udp_crypto_gateway_run_direct_smoke_checked(case_id);
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
        gateway_refresh_session_activity(session);
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
            g_last_lock_reason = GATEWAY_LOCK_REASON_AUTH_THRESHOLD;
            gateway_lock_session(session);
        }
        gateway_send_control_response(pcb, addr, port, msg_type, flags, session_id, seq_id, GATEWAY_CTRL_STATUS_AUTH_FAIL, NULL, 0U, binding_id);
        return;
    }

    if (gateway_check_and_update_seq(session, seq_id) != 0) {
        g_last_drop_reason = GATEWAY_DROP_REASON_REPLAY;
        g_diag_replay_seen = 1U;
        g_stat_drop_replay++;
        session->replay_failures++;
        if (session->replay_failures >= GATEWAY_REPLAY_FAILURE_THRESHOLD) {
            g_last_lock_reason = GATEWAY_LOCK_REASON_REPLAY_THRESHOLD;
            gateway_lock_session(session);
        }
        gateway_send_control_response(pcb, addr, port, msg_type, flags, session_id, seq_id, GATEWAY_CTRL_STATUS_REPLAY, NULL, 0U, binding_id);
        return;
    }

    session->auth_failures = 0U;
    session->replay_failures = 0U;

    switch (msg_type) {
    case GATEWAY_CTRL_MSG_SET_KEY:
        {
            const uint8_t *user_key = &packet[GATEWAY_CONTROL_HEADER_BYTES];
            uint8_t reauth_pending = g_diag_reauth_pending;

            if (payload_len != 16U) {
                status_code = GATEWAY_CTRL_STATUS_BAD_LENGTH;
                break;
            }
            if ((flags & (GATEWAY_ALGO_FLAG_AES | GATEWAY_ALGO_FLAG_SM4)) == 0U) {
                status_code = GATEWAY_CTRL_STATUS_BAD_LENGTH;
                break;
            }
            if ((flags & GATEWAY_ALGO_FLAG_AES) != 0U) {
                gateway_derive_effective_key(user_key, session->device_dna, GATEWAY_ALGO_AES, session->effective_key_aes);
            }
            if ((flags & GATEWAY_ALGO_FLAG_SM4) != 0U) {
                gateway_derive_effective_key(user_key, session->device_dna, GATEWAY_ALGO_SM4, session->effective_key_sm4);
            }
            session->authorized_algos |= (uint8_t)(flags & (GATEWAY_ALGO_FLAG_AES | GATEWAY_ALGO_FLAG_SM4));
            g_last_drop_reason = GATEWAY_DROP_REASON_NONE;
            g_last_lock_reason = GATEWAY_LOCK_REASON_NONE;
            g_diag_acl_hit_seen = 0U;
            g_diag_replay_seen = 0U;
            g_diag_timeout_seen = 0U;
            g_diag_reauth_seen = 0U;
            g_diag_reauth_pending = 0U;
            if (reauth_pending != 0U) {
                g_diag_reauth_seen = 1U;
            }
            gateway_hw_sync_cache_invalidate();
            break;
        }

    case GATEWAY_CTRL_MSG_LOCK:
        g_last_lock_reason = GATEWAY_LOCK_REASON_MANUAL;
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

    case GATEWAY_CTRL_MSG_ACL_WRITE: {
        uint32_t src_ip;
        uint16_t src_port;
        uint32_t dst_ip;
        uint16_t dst_port;
        uint8_t protocol;

        if (payload_len != GATEWAY_ACL_TUPLE_PAYLOAD_BYTES) {
            status_code = GATEWAY_CTRL_STATUS_BAD_LENGTH;
            break;
        }
        src_ip = gateway_load_be_word(&packet[GATEWAY_CONTROL_HEADER_BYTES + 0U]);
        src_port = gateway_load_be16(&packet[GATEWAY_CONTROL_HEADER_BYTES + 4U]);
        dst_ip = gateway_load_be_word(&packet[GATEWAY_CONTROL_HEADER_BYTES + 6U]);
        dst_port = gateway_load_be16(&packet[GATEWAY_CONTROL_HEADER_BYTES + 10U]);
        protocol = packet[GATEWAY_CONTROL_HEADER_BYTES + 12U];
        if (gateway_shadow_acl_write_rule(src_ip, src_port, dst_ip, dst_port, protocol) != 0) {
            status_code = GATEWAY_CTRL_STATUS_INTERNAL;
        }
        break;
    }

    case GATEWAY_CTRL_MSG_ACL_CLEAR:
        if (payload_len != 0U) {
            status_code = GATEWAY_CTRL_STATUS_BAD_LENGTH;
            break;
        }
        gateway_shadow_acl_clear_all();
        break;

    case GATEWAY_CTRL_MSG_ACL_STATUS:
        if (payload_len != 0U) {
            status_code = GATEWAY_CTRL_STATUS_BAD_LENGTH;
            break;
        }
        gateway_store_be_word(response_payload, gateway_shadow_wrap_read32(WRAP_REG_ACL_CNT));
        response_payload_len = 4U;
        break;

    default:
        status_code = GATEWAY_CTRL_STATUS_UNKNOWN_MSG;
        break;
    }

    if (status_code == GATEWAY_CTRL_STATUS_OK) {
        gateway_refresh_session_activity(session);
        g_stat_rx_ctrl_ok++;
#if UDP_GATEWAY_ENABLE_SHADOW_MIRROR
        xil_printf("LIVE_CTRL PASS msg_type=%u session=0x%08x\r\n",
                   (unsigned)msg_type,
                   GATEWAY_UART_U32(session_id));
        gateway_shadow_mark_milestone(GATEWAY_SHADOW_MILESTONE_LIVE_CTRL);
#endif
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
        g_last_drop_reason = GATEWAY_DROP_REASON_INVALID;
        g_stat_drops_invalid++;
        xil_printf("udp_crypto_gateway: drop invalid algo=%s local_port=%u len=%u\r\n",
                   gateway_algo_name((listener != NULL) ? listener->algo : GATEWAY_ALGO_AES),
                   (unsigned)((pcb != NULL) ? pcb->local_port : 0U),
                   (unsigned)payload_len);
#if UDP_GATEWAY_ENABLE_SHADOW_MIRROR
        xil_printf("SHADOW_INVALID_SKIP PASS local_port=%u len=%u\r\n",
                   (unsigned)((pcb != NULL) ? pcb->local_port : 0U),
                   (unsigned)payload_len);
        gateway_shadow_mark_milestone(GATEWAY_SHADOW_MILESTONE_INVALID_SKIP);
#endif
        pbuf_free(p);
        return;
    }

    session = gateway_find_session_by_ip(addr);
    if (!gateway_session_allows_algo(session, (listener != NULL) ? listener->algo : GATEWAY_ALGO_AES)) {
        g_last_drop_reason = GATEWAY_DROP_REASON_UNAUTHORIZED;
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
        g_last_drop_reason = GATEWAY_DROP_REASON_UNAUTHORIZED;
        g_stat_drop_unauthorized++;
        pbuf_free(p);
        return;
    }

    copied = pbuf_copy_partial(p, local_payload, payload_len, 0U);
    pbuf_free(p);
    if (copied != payload_len) {
        g_last_drop_reason = GATEWAY_DROP_REASON_INVALID;
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
                   payload_len) == 0) {
        g_stat_rx_data_ok++;
        xil_printf("udp_crypto_gateway: queued algo=%s local_port=%u len=%u from port=%u\r\n",
                   gateway_algo_name((listener != NULL) ? listener->algo : GATEWAY_ALGO_AES),
                   (unsigned)((pcb != NULL) ? pcb->local_port : 0U),
                   (unsigned)payload_len,
                   (unsigned)port);
        (void)gateway_shadow_submit_live_mirror((listener != NULL) ? listener->algo : GATEWAY_ALGO_AES,
                                                (uint16_t)((pcb != NULL) ? pcb->local_port : 0U),
                                                addr,
                                                port,
                                                local_payload,
                                                payload_len);
    } else {
        g_stat_drops_busy++;
        xil_printf("udp_crypto_gateway: queue full algo=%s local_port=%u len=%u\r\n",
                   gateway_algo_name((listener != NULL) ? listener->algo : GATEWAY_ALGO_AES),
                   (unsigned)((pcb != NULL) ? pcb->local_port : 0U),
                   (unsigned)payload_len);
    }
}

static int send_active_response(void)
{
    struct pbuf *resp;
    err_t err;
    gateway_session_t *active_session;

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

    active_session = gateway_find_session_by_id(&g_active_job.remote_ip, g_active_job.session_id);
    gateway_refresh_session_activity(active_session);
    g_stat_completed++;
    g_stat_tx_ok++;
    xil_printf("udp_crypto_gateway: response sent algo=%s local_port=%u len=%u total=%u\r\n",
               gateway_algo_name(g_active_job.algo),
               (unsigned)gateway_reply_local_port(&g_active_job),
               (unsigned)g_active_job.payload_len,
               GATEWAY_UART_U32(g_stat_completed));
#if UDP_GATEWAY_ENABLE_SHADOW_MIRROR
    if (g_active_job.algo == GATEWAY_ALGO_AES) {
        xil_printf("LIVE_AES PASS len=%u\r\n",
                   (unsigned)g_active_job.payload_len);
        gateway_shadow_mark_milestone(GATEWAY_SHADOW_MILESTONE_LIVE_AES);
    } else {
        xil_printf("LIVE_SM4 PASS len=%u\r\n",
                   (unsigned)g_active_job.payload_len);
        gateway_shadow_mark_milestone(GATEWAY_SHADOW_MILESTONE_LIVE_SM4);
    }
#endif
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
    xil_printf("udp_crypto_gateway: job_start seq=%u algo=%s local_port=%u len=%u src=%u.%u.%u.%u:%u state=%s qdepth=%u\r\n",
               GATEWAY_UART_U32(g_stat_jobs_started),
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

    status = gateway_backend_read_status();
    switch (g_job_state) {
    case JOB_WAIT_ENGINE_READY:
        if ((status & STATUS_SYS_READY) == 0U) {
            if (gateway_wait_or_drop("engine_ready", status, GATEWAY_WAIT_ENGINE_POLLS) != 0) {
                return;
            }
            return;
        }
        if (gateway_log_block_details(&g_active_job) || (g_active_offset == 0U)) {
            xil_printf("udp_crypto_gateway: state=%s ready status=0x%08x offset=%u/%u\r\n",
                       job_state_name(g_job_state),
                       GATEWAY_UART_U32(status),
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
        xil_printf("udp_crypto_gateway: ctrl_write algo=%s begin value=0x%08x\r\n",
                   gateway_algo_name(g_active_job.algo),
                   GATEWAY_UART_U32(ctrl_word));
        gateway_backend_write_ctrl(ctrl_word);
        xil_printf("udp_crypto_gateway: ctrl_written algo=%s status_after=0x%08x\r\n",
                   gateway_algo_name(g_active_job.algo),
                   GATEWAY_UART_U32(gateway_backend_read_status()));
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
            xil_printf("udp_crypto_gateway: state=%s ready status=0x%08x offset=%u/%u\r\n",
                       job_state_name(g_job_state),
                       GATEWAY_UART_U32(status),
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
            xil_printf("udp_crypto_gateway: push_block done status_after=0x%08x data0=%02x%02x%02x%02x\r\n",
                       GATEWAY_UART_U32(gateway_backend_read_status()),
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
            xil_printf("udp_crypto_gateway: state=%s block_done status=0x%08x offset=%u/%u\r\n",
                       job_state_name(g_job_state),
                       GATEWAY_UART_U32(status),
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
            xil_printf("udp_crypto_gateway: response failed failures=%u\r\n",
                       GATEWAY_UART_U32(g_stat_failures));
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
    xil_printf("CRYPTO_BASE_ADDR = 0x%08x", GATEWAY_UART_ADDR(CRYPTO_BASE_ADDR));
#ifdef CRYPTO_BASE_FALLBACK
    xil_printf(" (fallback)");
#endif
    xil_printf("\n\r");
}

#if !UDP_GATEWAY_SMOKE_ONLY_BUILD
int start_application(void)
{
    err_t err;

    gateway_backend_select_direct_mmio();
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
    g_last_drop_reason = GATEWAY_DROP_REASON_NONE;
    g_last_lock_reason = GATEWAY_LOCK_REASON_NONE;
    g_diag_acl_hit_seen = 0U;
    g_diag_replay_seen = 0U;
    g_diag_timeout_seen = 0U;
    g_diag_reauth_seen = 0U;
    g_diag_reauth_pending = 0U;
    gateway_hw_sync_cache_invalidate();
    g_next_session_id = 1U;
#if UDP_GATEWAY_ENABLE_SHADOW_MIRROR
    if (gateway_shadow_init_runtime() != 0) {
        g_shadow_run_state = GATEWAY_SHADOW_RUN_DISABLED;
        xil_printf("udp_crypto_gateway: shadow init failed, live path continues\r\n");
    }
#endif

    if (!gateway_backend_supports(GATEWAY_BACKEND_CAP_CRYPTO_SYNC)) {
        xil_printf("udp_crypto_gateway: direct backend capability missing kind=%u caps=0x%08x\r\n",
                   (unsigned)gateway_backend_kind(),
                   GATEWAY_UART_U32(gateway_backend_caps()));
        return -5;
    }

    xil_printf("udp_crypto_gateway: custom PL clock/reset path already prepared\r\n");
    dump_pl_registers();

    xil_printf("udp_crypto_gateway: REG_STATUS initial=0x%08x\r\n",
               GATEWAY_UART_U32(gateway_backend_read_status()));

    g_udp_pcb_aes = udp_new_ip_type(IPADDR_TYPE_ANY);
    g_udp_pcb_sm4 = udp_new_ip_type(IPADDR_TYPE_ANY);
    g_udp_pcb_ctrl = udp_new_ip_type(IPADDR_TYPE_ANY);
    if ((g_udp_pcb_aes == NULL) || (g_udp_pcb_sm4 == NULL) || (g_udp_pcb_ctrl == NULL)) {
        xil_printf("udp_crypto_gateway: udp_new_ip_type failed aes=0x%08x sm4=0x%08x ctrl=0x%08x\r\n",
                   GATEWAY_UART_ADDR(g_udp_pcb_aes),
                   GATEWAY_UART_ADDR(g_udp_pcb_sm4),
                   GATEWAY_UART_ADDR(g_udp_pcb_ctrl));
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

    xil_printf("udp_crypto_gateway: udp_bind AES ok pcb=0x%08x local_port=%u\r\n",
               GATEWAY_UART_ADDR(g_udp_pcb_aes),
               (unsigned)g_udp_pcb_aes->local_port);
    xil_printf("udp_crypto_gateway: udp_bind SM4 ok pcb=0x%08x local_port=%u\r\n",
               GATEWAY_UART_ADDR(g_udp_pcb_sm4),
               (unsigned)g_udp_pcb_sm4->local_port);
    xil_printf("udp_crypto_gateway: udp_bind CTRL ok pcb=0x%08x local_port=%u\r\n",
               GATEWAY_UART_ADDR(g_udp_pcb_ctrl),
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
    gateway_shadow_service();
    return 0;
}
#endif
