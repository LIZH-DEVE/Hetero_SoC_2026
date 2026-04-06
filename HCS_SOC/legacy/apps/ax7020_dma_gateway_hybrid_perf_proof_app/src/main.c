#include <stdint.h>
#include <string.h>

#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "xtime_l.h"

#include "dma_hw_regs.h"
#include "dma_mvp_ps_driver_ref.h"

#define HYBRID_DMA_BASEADDR 0x40001000u
#define HYBRID_DMA_CTRL_REG DMA_CSR_CTRL
#define HYBRID_DMA_LOOPBACK_MODE_REG DMA_CSR_LOOPBACK_MODE
#define HYBRID_DMA_KEY0_REG 0x28u
#define HYBRID_DMA_KEY1_REG 0x2Cu
#define HYBRID_DMA_KEY2_REG 0x30u
#define HYBRID_DMA_KEY3_REG 0x34u
#define HYBRID_DMA_KEY4_REG 0x74u
#define HYBRID_DMA_KEY5_REG 0x78u
#define HYBRID_DMA_KEY6_REG 0x7Cu
#define HYBRID_DMA_KEY7_REG 0x80u

#define HYBRID_RING_ENTRY_COUNT 2048u
#define HYBRID_USABLE_RING_ENTRIES (HYBRID_RING_ENTRY_COUNT - 1u)
#define HYBRID_DEFAULT_BENCH_REPEATS 1000u
#define HYBRID_BENCH_LENGTH_COUNT 5u
#define HYBRID_MAX_PAYLOAD_BYTES 1472u
#define HYBRID_BATCH_STRIDE_BYTES DMA_ALIGNMENT_BYTES
#define HYBRID_POLL_TIMEOUT 3000000u
#define HYBRID_BLOCK_BYTES 16u

typedef enum {
    HYBRID_ALGO_AES = 0,
    HYBRID_ALGO_SM4 = 1
} hybrid_algo_t;

typedef struct {
    dma_ring_desc_t ring[HYBRID_RING_ENTRY_COUNT];
    uint8_t guard[DMA_CACHELINE_BYTES];
} hybrid_desc_region_t;

typedef struct {
    uint8_t payload[HYBRID_MAX_PAYLOAD_BYTES + HYBRID_BATCH_STRIDE_BYTES];
} hybrid_src_region_t;

typedef struct {
    uint8_t payload[(HYBRID_MAX_PAYLOAD_BYTES + HYBRID_BATCH_STRIDE_BYTES) * HYBRID_DEFAULT_BENCH_REPEATS];
} hybrid_dst_region_t;

typedef struct {
    uint32_t batch_descriptor_count;
    uint32_t single_launch_used;
    uint32_t doorbell_count;
    uint32_t last_descriptor_poll_count;
    uint32_t actual_len_mismatch_count;
    uint32_t cipher_mismatch_count;
    uint32_t descriptor_error_count;
    uint32_t completion_timeout_count;
} hybrid_batch_diag_t;

typedef struct {
    hybrid_algo_t algo;
    uint16_t payload_len;
    uint32_t sw_us;
    uint32_t hw_us;
    hybrid_batch_diag_t diag;
} hybrid_bench_row_t;

static hybrid_desc_region_t g_desc_region
    __attribute__((aligned(DMA_ALIGNMENT_BYTES), section(".hybrid_desc_region")));
static hybrid_src_region_t g_src_region
    __attribute__((aligned(DMA_ALIGNMENT_BYTES), section(".hybrid_src_region")));
static hybrid_dst_region_t g_dst_region
    __attribute__((aligned(DMA_ALIGNMENT_BYTES), section(".hybrid_dst_region")));
static uint8_t g_sw_output[HYBRID_MAX_PAYLOAD_BYTES]
    __attribute__((aligned(DMA_ALIGNMENT_BYTES)));
static uint8_t g_expected_output[HYBRID_MAX_PAYLOAD_BYTES]
    __attribute__((aligned(DMA_ALIGNMENT_BYTES)));

static const uint16_t g_hybrid_bench_lengths[HYBRID_BENCH_LENGTH_COUNT] = { 16u, 32u, 128u, 512u, 1472u };

static const uint8_t g_hybrid_aes_key[16] = {
    0x2bU, 0x7eU, 0x15U, 0x16U, 0x28U, 0xaeU, 0xd2U, 0xa6U,
    0xabU, 0xf7U, 0x15U, 0x88U, 0x09U, 0xcfU, 0x4fU, 0x3cU
};

static const uint8_t g_hybrid_sm4_key[16] = {
    0x01U, 0x23U, 0x45U, 0x67U, 0x89U, 0xabU, 0xcdU, 0xefU,
    0xfeU, 0xdcU, 0xbaU, 0x98U, 0x76U, 0x54U, 0x32U, 0x10U
};

static const uint8_t g_hybrid_aes_sbox[256] = {
    0x63U, 0x7cU, 0x77U, 0x7bU, 0xf2U, 0x6bU, 0x6fU, 0xc5U, 0x30U, 0x01U, 0x67U, 0x2bU, 0xfeU, 0xd7U, 0xabU, 0x76U,
    0xcaU, 0x82U, 0xc9U, 0x7dU, 0xfaU, 0x59U, 0x47U, 0xf0U, 0xadU, 0xd4U, 0xa2U, 0xafU, 0x9cU, 0xa4U, 0x72U, 0xc0U,
    0xb7U, 0xfdU, 0x93U, 0x26U, 0x36U, 0x3fU, 0xf7U, 0xccU, 0x34U, 0xa5U, 0xe5U, 0xf1U, 0x71U, 0xd8U, 0x31U, 0x15U,
    0x04U, 0xc7U, 0x23U, 0xc3U, 0x18U, 0x96U, 0x05U, 0x9aU, 0x07U, 0x12U, 0x80U, 0xe2U, 0xebU, 0x27U, 0xb2U, 0x75U,
    0x09U, 0x83U, 0x2cU, 0x1aU, 0x1bU, 0x6eU, 0x5aU, 0xa0U, 0x52U, 0x3bU, 0xd6U, 0xb3U, 0x29U, 0xe3U, 0x2fU, 0x84U,
    0x53U, 0xd1U, 0x00U, 0xedU, 0x20U, 0xfcU, 0xb1U, 0x5bU, 0x6aU, 0xcbU, 0xbeU, 0x39U, 0x4aU, 0x4cU, 0x58U, 0xcfU,
    0xd0U, 0xefU, 0xaaU, 0xfbU, 0x43U, 0x4dU, 0x33U, 0x85U, 0x45U, 0xf9U, 0x02U, 0x7fU, 0x50U, 0x3cU, 0x9fU, 0xa8U,
    0x51U, 0xa3U, 0x40U, 0x8fU, 0x92U, 0x9dU, 0x38U, 0xf5U, 0xbcU, 0xb6U, 0xdaU, 0x21U, 0x10U, 0xffU, 0xf3U, 0xd2U,
    0xcdU, 0x0cU, 0x13U, 0xecU, 0x5fU, 0x97U, 0x44U, 0x17U, 0xc4U, 0xa7U, 0x7eU, 0x3dU, 0x64U, 0x5dU, 0x19U, 0x73U,
    0x60U, 0x81U, 0x4fU, 0xdcU, 0x22U, 0x2aU, 0x90U, 0x88U, 0x46U, 0xeeU, 0xb8U, 0x14U, 0xdeU, 0x5eU, 0x0bU, 0xdbU,
    0xe0U, 0x32U, 0x3aU, 0x0aU, 0x49U, 0x06U, 0x24U, 0x5cU, 0xc2U, 0xd3U, 0xacU, 0x62U, 0x91U, 0x95U, 0xe4U, 0x79U,
    0xe7U, 0xc8U, 0x37U, 0x6dU, 0x8dU, 0xd5U, 0x4eU, 0xa9U, 0x6cU, 0x56U, 0xf4U, 0xeaU, 0x65U, 0x7aU, 0xaeU, 0x08U,
    0xbaU, 0x78U, 0x25U, 0x2eU, 0x1cU, 0xa6U, 0xb4U, 0xc6U, 0xe8U, 0xddU, 0x74U, 0x1fU, 0x4bU, 0xbdU, 0x8bU, 0x8aU,
    0x70U, 0x3eU, 0xb5U, 0x66U, 0x48U, 0x03U, 0xf6U, 0x0eU, 0x61U, 0x35U, 0x57U, 0xb9U, 0x86U, 0xc1U, 0x1dU, 0x9eU,
    0xe1U, 0xf8U, 0x98U, 0x11U, 0x69U, 0xd9U, 0x8eU, 0x94U, 0x9bU, 0x1eU, 0x87U, 0xe9U, 0xceU, 0x55U, 0x28U, 0xdfU,
    0x8cU, 0xa1U, 0x89U, 0x0dU, 0xbfU, 0xe6U, 0x42U, 0x68U, 0x41U, 0x99U, 0x2dU, 0x0fU, 0xb0U, 0x54U, 0xbbU, 0x16U
};

static const uint8_t g_hybrid_sm4_sbox[256] = {
    0xd6U, 0x90U, 0xe9U, 0xfeU, 0xccU, 0xe1U, 0x3dU, 0xb7U, 0x16U, 0xb6U, 0x14U, 0xc2U, 0x28U, 0xfbU, 0x2cU, 0x05U,
    0x2bU, 0x67U, 0x9aU, 0x76U, 0x2aU, 0xbeU, 0x04U, 0xc3U, 0xaaU, 0x44U, 0x13U, 0x26U, 0x49U, 0x86U, 0x06U, 0x99U,
    0x9cU, 0x42U, 0x50U, 0xf4U, 0x91U, 0xefU, 0x98U, 0x7aU, 0x33U, 0x54U, 0x0bU, 0x43U, 0xedU, 0xcfU, 0xacU, 0x62U,
    0xe4U, 0xb3U, 0x1cU, 0xa9U, 0xc9U, 0x08U, 0xe8U, 0x95U, 0x80U, 0xdfU, 0x94U, 0xfaU, 0x75U, 0x8fU, 0x3fU, 0xa6U,
    0x47U, 0x07U, 0xa7U, 0xfcU, 0xf3U, 0x73U, 0x17U, 0xbaU, 0x83U, 0x59U, 0x3cU, 0x19U, 0xe6U, 0x85U, 0x4fU, 0xa8U,
    0x68U, 0x6bU, 0x81U, 0xb2U, 0x71U, 0x64U, 0xdaU, 0x8bU, 0xf8U, 0xebU, 0x0fU, 0x4bU, 0x70U, 0x56U, 0x9dU, 0x35U,
    0x1eU, 0x24U, 0x0eU, 0x5eU, 0x63U, 0x58U, 0xd1U, 0xa2U, 0x25U, 0x22U, 0x7cU, 0x3bU, 0x01U, 0x21U, 0x78U, 0x87U,
    0xd4U, 0x00U, 0x46U, 0x57U, 0x9fU, 0xd3U, 0x27U, 0x52U, 0x4cU, 0x36U, 0x02U, 0xe7U, 0xa0U, 0xc4U, 0xc8U, 0x9eU,
    0xeaU, 0xbfU, 0x8aU, 0xd2U, 0x40U, 0xc7U, 0x38U, 0xb5U, 0xa3U, 0xf7U, 0xf2U, 0xceU, 0xf9U, 0x61U, 0x15U, 0xa1U,
    0xe0U, 0xaeU, 0x5dU, 0xa4U, 0x9bU, 0x34U, 0x1aU, 0x55U, 0xadU, 0x93U, 0x32U, 0x30U, 0xf5U, 0x8cU, 0xb1U, 0xe3U,
    0x1dU, 0xf6U, 0xe2U, 0x2eU, 0x82U, 0x66U, 0xcaU, 0x60U, 0xc0U, 0x29U, 0x23U, 0xabU, 0x0dU, 0x53U, 0x4eU, 0x6fU,
    0xd5U, 0xdbU, 0x37U, 0x45U, 0xdeU, 0xfdU, 0x8eU, 0x2fU, 0x03U, 0xffU, 0x6aU, 0x72U, 0x6dU, 0x6cU, 0x5bU, 0x51U,
    0x8dU, 0x1bU, 0xafU, 0x92U, 0xbbU, 0xddU, 0xbcU, 0x7fU, 0x11U, 0xd9U, 0x5cU, 0x41U, 0x1fU, 0x10U, 0x5aU, 0xd8U,
    0x0aU, 0xc1U, 0x31U, 0x88U, 0xa5U, 0xcdU, 0x7bU, 0xbdU, 0x2dU, 0x74U, 0xd0U, 0x12U, 0xb8U, 0xe5U, 0xb4U, 0xb0U,
    0x89U, 0x69U, 0x97U, 0x4aU, 0x0cU, 0x96U, 0x77U, 0x7eU, 0x65U, 0xb9U, 0xf1U, 0x09U, 0xc5U, 0x6eU, 0xc6U, 0x84U,
    0x18U, 0xf0U, 0x7dU, 0xecU, 0x3aU, 0xdcU, 0x4dU, 0x20U, 0x79U, 0xeeU, 0x5fU, 0x3eU, 0xd7U, 0xcbU, 0x39U, 0x48U
};

static const uint32_t g_hybrid_sm4_fk[4] = {
    0xA3B1BAC6U, 0x56AA3350U, 0x677D9197U, 0xB27022DCU
};

static const uint32_t g_hybrid_sm4_ck[32] = {
    0x00070E15U, 0x1C232A31U, 0x383F464DU, 0x545B6269U,
    0x70777E85U, 0x8C939AA1U, 0xA8AFB6BDU, 0xC4CBD2D9U,
    0xE0E7EEF5U, 0xFC030A11U, 0x181F262DU, 0x343B4249U,
    0x50575E65U, 0x6C737A81U, 0x888F969DU, 0xA4ABB2B9U,
    0xC0C7CED5U, 0xDCE3EAF1U, 0xF8FF060DU, 0x141B2229U,
    0x30373E45U, 0x4C535A61U, 0x686F767DU, 0x848B9299U,
    0xA0A7AEB5U, 0xBCC3CAD1U, 0xD8DFE6EDU, 0xF4FB0209U,
    0x10171E25U, 0x2C333A41U, 0x484F565DU, 0x646B7279U
};

static uint32_t align_up_u32(uint32_t value, uint32_t alignment)
{
    return (value + alignment - 1u) & ~(alignment - 1u);
}

static uint32_t hybrid_load_be_word(const uint8_t *data)
{
    return ((uint32_t)data[0] << 24) |
           ((uint32_t)data[1] << 16) |
           ((uint32_t)data[2] << 8) |
           (uint32_t)data[3];
}

static void hybrid_store_be_word(uint8_t *out, uint32_t word)
{
    out[0] = (uint8_t)((word >> 24) & 0xffu);
    out[1] = (uint8_t)((word >> 16) & 0xffu);
    out[2] = (uint8_t)((word >> 8) & 0xffu);
    out[3] = (uint8_t)(word & 0xffu);
}

static uint32_t hybrid_ticks_to_us(XTime delta_ticks)
{
    return (uint32_t)(((uint64_t)delta_ticks * 1000000ULL) / (uint64_t)COUNTS_PER_SECOND);
}

static const char *hybrid_algo_name(hybrid_algo_t algo)
{
    return (algo == HYBRID_ALGO_SM4) ? "sm4" : "aes";
}

static const char *hybrid_algo_upper_name(hybrid_algo_t algo)
{
    return (algo == HYBRID_ALGO_SM4) ? "SM4" : "AES";
}

static const uint8_t *hybrid_key_for_algo(hybrid_algo_t algo)
{
    return (algo == HYBRID_ALGO_SM4) ? g_hybrid_sm4_key : g_hybrid_aes_key;
}

static inline void hybrid_dma_write32(uint32_t offset, uint32_t value)
{
    Xil_Out32((UINTPTR)(HYBRID_DMA_BASEADDR + offset), value);
    DATA_SYNC;
}

static inline uint32_t hybrid_dma_read32(uint32_t offset)
{
    uint32_t value = Xil_In32((UINTPTR)(HYBRID_DMA_BASEADDR + offset));
    DATA_SYNC;
    return value;
}

static int poll_last_descriptor_done(volatile dma_ring_desc_t *desc,
                                     uint32_t *csw_out,
                                     uint32_t *poll_count_out)
{
    uint32_t poll_count;

    for (poll_count = 0u; poll_count < HYBRID_POLL_TIMEOUT; ++poll_count) {
        int rc = dma_ring_poll_csw(desc, csw_out);
        if (rc == 0) {
            if (poll_count_out != 0) {
                *poll_count_out = poll_count + 1u;
            }
            return 0;
        }
        if (rc < 0) {
            if (poll_count_out != 0) {
                *poll_count_out = poll_count + 1u;
            }
            return rc;
        }
    }

    if (poll_count_out != 0) {
        *poll_count_out = HYBRID_POLL_TIMEOUT;
    }
    return -1;
}

static void hybrid_print_timeout_diag(hybrid_algo_t algo,
                                      uint16_t payload_len,
                                      const dma_ring_ctx_t *ctx)
{
    volatile dma_ring_desc_t *first_desc = &g_desc_region.ring[0];
    volatile dma_ring_desc_t *last_desc = &g_desc_region.ring[HYBRID_DEFAULT_BENCH_REPEATS - 1u];
    uint32_t first_csw = 0u;
    uint32_t last_csw = 0u;
    uint32_t first_actual_len;
    uint32_t last_actual_len;

    (void)dma_ring_poll_csw(first_desc, &first_csw);
    (void)dma_ring_poll_csw(last_desc, &last_csw);
    first_actual_len = dma_ring_read_actual_len(first_desc);
    last_actual_len = dma_ring_read_actual_len(last_desc);

    uint32_t debug_status = hybrid_dma_read32(DMA_CSR_DEBUG_STATUS);
    uint32_t debug_source_progress = hybrid_dma_read32(DMA_CSR_DEBUG_SOURCE_PROGRESS);
    uint32_t debug_sink_progress = hybrid_dma_read32(DMA_CSR_DEBUG_SINK_PROGRESS);

    xil_printf(
        "PROOF_TIMEOUT_DIAG algo=%s length=%u hw_head=%u sw_tail=%u ring_size=%u status=0x%08x irq_status=0x%08x dbg_status=0x%08x dbg_src=0x%08x dbg_sink=0x%08x desc0_csw=0x%08x desc0_actual_len=%u desc_last_csw=0x%08x desc_last_actual_len=%u\r\n",
        hybrid_algo_name(algo),
        (unsigned int)payload_len,
        (unsigned int)hybrid_dma_read32(DMA_CSR_RING_HW_HEAD),
        (unsigned int)hybrid_dma_read32(DMA_CSR_RING_SW_TAIL),
        (unsigned int)hybrid_dma_read32(DMA_CSR_RING_SIZE),
        (unsigned int)hybrid_dma_read32(DMA_CSR_STATUS),
        (unsigned int)dma_ring_irq_status(ctx),
        (unsigned int)debug_status,
        (unsigned int)debug_source_progress,
        (unsigned int)debug_sink_progress,
        (unsigned int)first_csw,
        (unsigned int)first_actual_len,
        (unsigned int)last_csw,
        (unsigned int)last_actual_len);
}

static void hybrid_print_desc_error_diag(hybrid_algo_t algo,
                                         uint16_t payload_len,
                                         const dma_ring_ctx_t *ctx,
                                         int poll_rc,
                                         uint32_t last_csw)
{
    volatile dma_ring_desc_t *first_desc = &g_desc_region.ring[0];
    volatile dma_ring_desc_t *last_desc = &g_desc_region.ring[HYBRID_DEFAULT_BENCH_REPEATS - 1u];
    uint32_t first_csw = 0u;
    uint32_t first_actual_len;
    uint32_t last_actual_len;

    (void)dma_ring_poll_csw(first_desc, &first_csw);
    first_actual_len = dma_ring_read_actual_len(first_desc);
    last_actual_len = dma_ring_read_actual_len(last_desc);

    uint32_t debug_status = hybrid_dma_read32(DMA_CSR_DEBUG_STATUS);
    uint32_t debug_source_progress = hybrid_dma_read32(DMA_CSR_DEBUG_SOURCE_PROGRESS);
    uint32_t debug_sink_progress = hybrid_dma_read32(DMA_CSR_DEBUG_SINK_PROGRESS);

    xil_printf(
        "PROOF_DESC_ERR_DIAG algo=%s length=%u poll_rc=%d hw_head=%u sw_tail=%u ring_size=%u status=0x%08x irq_status=0x%08x dbg_status=0x%08x dbg_src=0x%08x dbg_sink=0x%08x desc0_csw=0x%08x desc0_actual_len=%u desc_last_csw=0x%08x desc_last_actual_len=%u\r\n",
        hybrid_algo_name(algo),
        (unsigned int)payload_len,
        poll_rc,
        (unsigned int)hybrid_dma_read32(DMA_CSR_RING_HW_HEAD),
        (unsigned int)hybrid_dma_read32(DMA_CSR_RING_SW_TAIL),
        (unsigned int)hybrid_dma_read32(DMA_CSR_RING_SIZE),
        (unsigned int)hybrid_dma_read32(DMA_CSR_STATUS),
        (unsigned int)dma_ring_irq_status(ctx),
        (unsigned int)debug_status,
        (unsigned int)debug_source_progress,
        (unsigned int)debug_sink_progress,
        (unsigned int)first_csw,
        (unsigned int)first_actual_len,
        (unsigned int)last_csw,
        (unsigned int)last_actual_len);
}

static void hybrid_print_mismatch_diag(hybrid_algo_t algo,
                                       uint16_t payload_len,
                                       const uint8_t *src,
                                       const uint8_t *expected,
                                       const uint8_t *actual)
{
    uint32_t sample_len = (payload_len < HYBRID_BLOCK_BYTES) ? payload_len : HYBRID_BLOCK_BYTES;
    uint32_t idx;

    xil_printf("PROOF_MISMATCH_DIAG algo=%s length=%u sample_len=%u\r\n",
               hybrid_algo_name(algo),
               (unsigned int)payload_len,
               (unsigned int)sample_len);

    xil_printf("PROOF_MISMATCH_SRC");
    for (idx = 0u; idx < sample_len; ++idx) {
        xil_printf("%02x", (unsigned int)src[idx]);
    }
    xil_printf("\r\n");

    xil_printf("PROOF_MISMATCH_EXP");
    for (idx = 0u; idx < sample_len; ++idx) {
        xil_printf("%02x", (unsigned int)expected[idx]);
    }
    xil_printf("\r\n");

    xil_printf("PROOF_MISMATCH_ACT");
    for (idx = 0u; idx < sample_len; ++idx) {
        xil_printf("%02x", (unsigned int)actual[idx]);
    }
    xil_printf("\r\n");

    xil_printf("PROOF_HW_BLOCK%08x%08x%08x%08x\r\n",
               (unsigned int)hybrid_dma_read32(DMA_CSR_DEBUG_PLAINTEXT_WORD0),
               (unsigned int)hybrid_dma_read32(DMA_CSR_DEBUG_PLAINTEXT_WORD1),
               (unsigned int)hybrid_dma_read32(DMA_CSR_DEBUG_PLAINTEXT_WORD2),
               (unsigned int)hybrid_dma_read32(DMA_CSR_DEBUG_PLAINTEXT_WORD3));
    xil_printf("PROOF_HW_KEY%08x%08x%08x%08x\r\n",
               (unsigned int)hybrid_dma_read32(DMA_CSR_DEBUG_KEY_WORD0),
               (unsigned int)hybrid_dma_read32(DMA_CSR_DEBUG_KEY_WORD1),
               (unsigned int)hybrid_dma_read32(DMA_CSR_DEBUG_KEY_WORD2),
               (unsigned int)hybrid_dma_read32(DMA_CSR_DEBUG_KEY_WORD3));
}

static uint8_t hybrid_aes_xtime(uint8_t value)
{
    return (uint8_t)((value << 1) ^ (((value & 0x80u) != 0u) ? 0x1bu : 0x00u));
}

static void hybrid_aes_add_round_key(uint8_t *state, const uint8_t *round_key)
{
    uint32_t i;

    for (i = 0u; i < 16u; ++i) {
        state[i] ^= round_key[i];
    }
}

static void hybrid_aes_sub_bytes(uint8_t *state)
{
    uint32_t i;

    for (i = 0u; i < 16u; ++i) {
        state[i] = g_hybrid_aes_sbox[state[i]];
    }
}

static void hybrid_aes_shift_rows(uint8_t *state)
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

static void hybrid_aes_mix_columns(uint8_t *state)
{
    uint32_t column;

    for (column = 0u; column < 4u; ++column) {
        uint8_t *c = &state[column * 4u];
        uint8_t a0 = c[0];
        uint8_t a1 = c[1];
        uint8_t a2 = c[2];
        uint8_t a3 = c[3];
        uint8_t t = (uint8_t)(a0 ^ a1 ^ a2 ^ a3);
        uint8_t u = a0;

        c[0] ^= t ^ hybrid_aes_xtime((uint8_t)(a0 ^ a1));
        c[1] ^= t ^ hybrid_aes_xtime((uint8_t)(a1 ^ a2));
        c[2] ^= t ^ hybrid_aes_xtime((uint8_t)(a2 ^ a3));
        c[3] ^= t ^ hybrid_aes_xtime((uint8_t)(a3 ^ u));
    }
}

static void hybrid_aes_expand_key(const uint8_t *key, uint8_t *round_keys)
{
    static const uint8_t rcon[10] = { 0x01u, 0x02u, 0x04u, 0x08u, 0x10u, 0x20u, 0x40u, 0x80u, 0x1bu, 0x36u };
    uint32_t generated = 16u;
    uint32_t rcon_index = 0u;
    uint8_t temp[4];

    memcpy(round_keys, key, 16u);
    while (generated < 176u) {
        temp[0] = round_keys[generated - 4u];
        temp[1] = round_keys[generated - 3u];
        temp[2] = round_keys[generated - 2u];
        temp[3] = round_keys[generated - 1u];

        if ((generated % 16u) == 0u) {
            uint8_t rotate = temp[0];
            temp[0] = g_hybrid_aes_sbox[temp[1]] ^ rcon[rcon_index++];
            temp[1] = g_hybrid_aes_sbox[temp[2]];
            temp[2] = g_hybrid_aes_sbox[temp[3]];
            temp[3] = g_hybrid_aes_sbox[rotate];
        }

        round_keys[generated] = round_keys[generated - 16u] ^ temp[0];
        generated++;
        round_keys[generated] = round_keys[generated - 16u] ^ temp[1];
        generated++;
        round_keys[generated] = round_keys[generated - 16u] ^ temp[2];
        generated++;
        round_keys[generated] = round_keys[generated - 16u] ^ temp[3];
        generated++;
    }
}

static void hybrid_aes_encrypt_block_sw(const uint8_t *round_keys, const uint8_t *in_block, uint8_t *out_block)
{
    uint8_t state[16];
    uint32_t round;

    memcpy(state, in_block, 16u);
    hybrid_aes_add_round_key(state, &round_keys[0]);

    for (round = 1u; round < 10u; ++round) {
        hybrid_aes_sub_bytes(state);
        hybrid_aes_shift_rows(state);
        hybrid_aes_mix_columns(state);
        hybrid_aes_add_round_key(state, &round_keys[round * 16u]);
    }

    hybrid_aes_sub_bytes(state);
    hybrid_aes_shift_rows(state);
    hybrid_aes_add_round_key(state, &round_keys[160u]);
    memcpy(out_block, state, 16u);
}

static uint32_t hybrid_rotate_left32(uint32_t value, uint32_t shift)
{
    return (value << shift) | (value >> (32u - shift));
}

static uint32_t hybrid_sm4_tau(uint32_t value)
{
    return ((uint32_t)g_hybrid_sm4_sbox[(value >> 24) & 0xffu] << 24) |
           ((uint32_t)g_hybrid_sm4_sbox[(value >> 16) & 0xffu] << 16) |
           ((uint32_t)g_hybrid_sm4_sbox[(value >> 8) & 0xffu] << 8) |
           (uint32_t)g_hybrid_sm4_sbox[value & 0xffu];
}

static uint32_t hybrid_sm4_l(uint32_t value)
{
    return value ^ hybrid_rotate_left32(value, 2u) ^ hybrid_rotate_left32(value, 10u) ^
           hybrid_rotate_left32(value, 18u) ^ hybrid_rotate_left32(value, 24u);
}

static uint32_t hybrid_sm4_l_prime(uint32_t value)
{
    return value ^ hybrid_rotate_left32(value, 13u) ^ hybrid_rotate_left32(value, 23u);
}

static void hybrid_sm4_expand_key(const uint8_t *key, uint32_t *round_keys)
{
    uint32_t k[36];
    uint32_t i;

    k[0] = hybrid_load_be_word(&key[0]) ^ g_hybrid_sm4_fk[0];
    k[1] = hybrid_load_be_word(&key[4]) ^ g_hybrid_sm4_fk[1];
    k[2] = hybrid_load_be_word(&key[8]) ^ g_hybrid_sm4_fk[2];
    k[3] = hybrid_load_be_word(&key[12]) ^ g_hybrid_sm4_fk[3];

    for (i = 0u; i < 32u; ++i) {
        uint32_t mix = k[i + 1u] ^ k[i + 2u] ^ k[i + 3u] ^ g_hybrid_sm4_ck[i];
        k[i + 4u] = k[i] ^ hybrid_sm4_l_prime(hybrid_sm4_tau(mix));
        round_keys[i] = k[i + 4u];
    }
}

static void hybrid_sm4_encrypt_block_sw(const uint32_t *round_keys, const uint8_t *in_block, uint8_t *out_block)
{
    uint32_t x[36];
    uint32_t i;

    x[0] = hybrid_load_be_word(&in_block[0]);
    x[1] = hybrid_load_be_word(&in_block[4]);
    x[2] = hybrid_load_be_word(&in_block[8]);
    x[3] = hybrid_load_be_word(&in_block[12]);

    for (i = 0u; i < 32u; ++i) {
        uint32_t mix = x[i + 1u] ^ x[i + 2u] ^ x[i + 3u] ^ round_keys[i];
        x[i + 4u] = x[i] ^ hybrid_sm4_l(hybrid_sm4_tau(mix));
    }

    hybrid_store_be_word(&out_block[0], x[35]);
    hybrid_store_be_word(&out_block[4], x[34]);
    hybrid_store_be_word(&out_block[8], x[33]);
    hybrid_store_be_word(&out_block[12], x[32]);
}

static int hybrid_sw_encrypt_buffer(hybrid_algo_t algo,
                                    const uint8_t *key,
                                    const uint8_t *input,
                                    uint8_t *output,
                                    uint16_t payload_len)
{
    uint16_t offset;

    if ((key == NULL) || (input == NULL) || (output == NULL) || ((payload_len % HYBRID_BLOCK_BYTES) != 0u)) {
        return -1;
    }

    if (algo == HYBRID_ALGO_SM4) {
        uint32_t round_keys[32];
        hybrid_sm4_expand_key(key, round_keys);
        for (offset = 0u; offset < payload_len; offset = (uint16_t)(offset + HYBRID_BLOCK_BYTES)) {
            hybrid_sm4_encrypt_block_sw(round_keys, &input[offset], &output[offset]);
        }
    } else {
        uint8_t round_keys[176];
        hybrid_aes_expand_key(key, round_keys);
        for (offset = 0u; offset < payload_len; offset = (uint16_t)(offset + HYBRID_BLOCK_BYTES)) {
            hybrid_aes_encrypt_block_sw(round_keys, &input[offset], &output[offset]);
        }
    }

    return 0;
}

static void prepare_source_payload(uint32_t payload_len)
{
    uint32_t idx;

    memset(&g_src_region, 0, sizeof(g_src_region));
    for (idx = 0u; idx < payload_len; ++idx) {
        g_src_region.payload[idx] = (uint8_t)(idx & 0xffu);
    }
    Xil_DCacheFlushRange((INTPTR)g_src_region.payload, payload_len);
}

static void hybrid_write_key_regs(const uint8_t *key)
{
    hybrid_dma_write32(HYBRID_DMA_KEY0_REG, hybrid_load_be_word(&key[12]));
    hybrid_dma_write32(HYBRID_DMA_KEY1_REG, hybrid_load_be_word(&key[8]));
    hybrid_dma_write32(HYBRID_DMA_KEY2_REG, hybrid_load_be_word(&key[4]));
    hybrid_dma_write32(HYBRID_DMA_KEY3_REG, hybrid_load_be_word(&key[0]));
    hybrid_dma_write32(HYBRID_DMA_KEY4_REG, 0u);
    hybrid_dma_write32(HYBRID_DMA_KEY5_REG, 0u);
    hybrid_dma_write32(HYBRID_DMA_KEY6_REG, 0u);
    hybrid_dma_write32(HYBRID_DMA_KEY7_REG, 0u);
}

static void hybrid_configure_crypto_context(hybrid_algo_t algo)
{
    (void)algo;
    hybrid_dma_write32(HYBRID_DMA_LOOPBACK_MODE_REG, 0u);
    hybrid_write_key_regs(hybrid_key_for_algo(algo));
    hybrid_dma_write32(HYBRID_DMA_CTRL_REG, DMA_CTRL_ENCRYPT);
}

static void hybrid_prepare_ring(dma_ring_ctx_t *ctx)
{
    dma_ring_init(ctx,
                  HYBRID_DMA_BASEADDR,
                  &g_desc_region.ring[0],
                  (uint32_t)(uintptr_t)&g_desc_region.ring[0],
                  HYBRID_RING_ENTRY_COUNT);
    dma_ring_soft_reset(ctx);
    dma_ring_init(ctx,
                  HYBRID_DMA_BASEADDR,
                  &g_desc_region.ring[0],
                  (uint32_t)(uintptr_t)&g_desc_region.ring[0],
                  HYBRID_RING_ENTRY_COUNT);
}

static void hybrid_print_addr_config(void)
{
    xil_printf(
        "PROOF_ADDR ring=0x%08x src=0x%08x dst0=0x%08x\r\n",
        (unsigned int)(uint32_t)(uintptr_t)&g_desc_region.ring[0],
        (unsigned int)(uint32_t)(uintptr_t)g_src_region.payload,
        (unsigned int)(uint32_t)(uintptr_t)&g_dst_region.payload[0]);
}

static uint8_t *hybrid_dst_slot_ptr(uint32_t slot_idx, uint32_t stride)
{
    return &g_dst_region.payload[slot_idx * stride];
}

static int run_sw_batch(hybrid_algo_t algo, uint16_t payload_len, uint32_t *sw_us_out)
{
    XTime sw_start;
    XTime sw_end;
    uint32_t repeat_idx;

    memset(g_sw_output, 0, sizeof(g_sw_output));
    XTime_GetTime(&sw_start);
    for (repeat_idx = 0u; repeat_idx < HYBRID_DEFAULT_BENCH_REPEATS; ++repeat_idx) {
        if (hybrid_sw_encrypt_buffer(algo,
                                     hybrid_key_for_algo(algo),
                                     g_src_region.payload,
                                     g_sw_output,
                                     payload_len) != 0) {
            return -1;
        }
    }
    XTime_GetTime(&sw_end);
    memcpy(g_expected_output, g_sw_output, payload_len);
    *sw_us_out = hybrid_ticks_to_us(sw_end - sw_start);
    return 0;
}

static int validate_hw_batch(hybrid_algo_t algo,
                             uint16_t payload_len,
                             uint32_t stride,
                             const uint8_t *expected_cipher,
                             hybrid_batch_diag_t *diag)
{
    uint32_t idx;
    uint8_t mismatch_reported = 0u;

    for (idx = 0u; idx < HYBRID_DEFAULT_BENCH_REPEATS; ++idx) {
        volatile dma_ring_desc_t *desc = &g_desc_region.ring[idx];
        uint32_t csw = 0u;
        uint32_t actual_len;
        uint8_t *slot_ptr = hybrid_dst_slot_ptr(idx, stride);

        if (dma_ring_poll_csw(desc, &csw) != 0) {
            diag->descriptor_error_count++;
        }
        actual_len = dma_ring_read_actual_len(desc);
        if (actual_len != payload_len) {
            diag->actual_len_mismatch_count++;
        }

        dma_ring_invalidate_result(slot_ptr, stride);
        if (memcmp(slot_ptr, expected_cipher, payload_len) != 0) {
            diag->cipher_mismatch_count++;
            if (mismatch_reported == 0u) {
                hybrid_print_mismatch_diag(algo,
                                           payload_len,
                                           g_src_region.payload,
                                           expected_cipher,
                                           slot_ptr);
                mismatch_reported = 1u;
            }
        }
    }

    return (diag->descriptor_error_count == 0u &&
            diag->actual_len_mismatch_count == 0u &&
            diag->cipher_mismatch_count == 0u)
               ? 0
               : -1;
}

static int run_hw_batch(hybrid_algo_t algo,
                        uint16_t payload_len,
                        uint32_t *hw_us_out,
                        hybrid_batch_diag_t *diag_out)
{
    dma_ring_ctx_t ctx;
    uint32_t idx;
    uint32_t stride;
    uint32_t poll_count = 0u;
    uint32_t csw = 0u;
    int poll_rc;
    XTime hw_start;
    XTime hw_end;
    hybrid_batch_diag_t diag;

    memset(&diag, 0, sizeof(diag));
    diag.batch_descriptor_count = HYBRID_DEFAULT_BENCH_REPEATS;
    diag.single_launch_used = 1u;
    diag.doorbell_count = 1u;

    if (HYBRID_DEFAULT_BENCH_REPEATS > HYBRID_USABLE_RING_ENTRIES) {
        return -2;
    }

    stride = align_up_u32(payload_len, DMA_ALIGNMENT_BYTES);
    memset(&g_desc_region, 0, sizeof(g_desc_region));
    memset(&g_dst_region, 0xA5, sizeof(g_dst_region));
    Xil_DCacheFlushRange((INTPTR)g_dst_region.payload, HYBRID_DEFAULT_BENCH_REPEATS * stride);
    hybrid_prepare_ring(&ctx);
    hybrid_configure_crypto_context(algo);

    for (idx = 0u; idx < HYBRID_DEFAULT_BENCH_REPEATS; ++idx) {
        int rc = dma_ring_submit_nodoorbell(
            &ctx,
            (uint32_t)(uintptr_t)hybrid_dst_slot_ptr(idx, stride),
            payload_len,
            (uint8_t)algo,
            g_src_region.payload,
            payload_len);
        if (rc != 0) {
            return rc;
        }
    }

    XTime_GetTime(&hw_start);
    if (dma_ring_publish_tail(&ctx) != 0) {
        return -3;
    }
    dma_ring_ring_doorbell(&ctx);
    poll_rc = poll_last_descriptor_done(&g_desc_region.ring[HYBRID_DEFAULT_BENCH_REPEATS - 1u],
                                        &csw,
                                        &poll_count);
    if (poll_rc == -1) {
        diag.completion_timeout_count = 1u;
        diag.last_descriptor_poll_count = poll_count;
        hybrid_print_timeout_diag(algo, payload_len, &ctx);
        *diag_out = diag;
        return -4;
    }
    if (poll_rc < 0) {
        diag.descriptor_error_count = 1u;
        diag.last_descriptor_poll_count = poll_count;
        hybrid_print_desc_error_diag(algo, payload_len, &ctx, poll_rc, csw);
        *diag_out = diag;
        return -6;
    }
    XTime_GetTime(&hw_end);

    diag.last_descriptor_poll_count = poll_count;
    *hw_us_out = hybrid_ticks_to_us(hw_end - hw_start);

    if (validate_hw_batch(algo, payload_len, stride, g_expected_output, &diag) != 0) {
        *diag_out = diag;
        return -5;
    }

    *diag_out = diag;
    return 0;
}

static void print_proof_row(const hybrid_bench_row_t *row)
{
    xil_printf(
        "PROOF_ROW algo=%s length=%u repeats=%u sw_us=%u hw_us=%u batch_descriptor_count=%u single_launch_used=%u doorbell_count=%u last_descriptor_poll_count=%u actual_len_mismatch_count=%u cipher_mismatch_count=%u descriptor_error_count=%u completion_timeout_count=%u\r\n",
        hybrid_algo_name(row->algo),
        (unsigned int)row->payload_len,
        (unsigned int)HYBRID_DEFAULT_BENCH_REPEATS,
        (unsigned int)row->sw_us,
        (unsigned int)row->hw_us,
        (unsigned int)row->diag.batch_descriptor_count,
        (unsigned int)row->diag.single_launch_used,
        (unsigned int)row->diag.doorbell_count,
        (unsigned int)row->diag.last_descriptor_poll_count,
        (unsigned int)row->diag.actual_len_mismatch_count,
        (unsigned int)row->diag.cipher_mismatch_count,
        (unsigned int)row->diag.descriptor_error_count,
        (unsigned int)row->diag.completion_timeout_count);
}

static int run_bench_for_algo(hybrid_algo_t algo)
{
    uint32_t length_idx;
    uint32_t record_count = 0u;

    hybrid_configure_crypto_context(algo);
    for (length_idx = 0u; length_idx < HYBRID_BENCH_LENGTH_COUNT; ++length_idx) {
        hybrid_bench_row_t row;
        int rc;

        memset(&row, 0, sizeof(row));
        row.algo = algo;
        row.payload_len = g_hybrid_bench_lengths[length_idx];

        prepare_source_payload(row.payload_len);
        rc = run_sw_batch(algo, row.payload_len, &row.sw_us);
        if (rc != 0) {
            xil_printf("PROOF_FAIL algo=%s length=%u stage=sw rc=%d\r\n",
                       hybrid_algo_name(algo),
                       (unsigned int)row.payload_len,
                       rc);
            return rc;
        }

        rc = run_hw_batch(algo, row.payload_len, &row.hw_us, &row.diag);
        print_proof_row(&row);
        if (rc != 0) {
            xil_printf("PROOF_FAIL algo=%s length=%u stage=hw rc=%d\r\n",
                       hybrid_algo_name(algo),
                       (unsigned int)row.payload_len,
                       rc);
            return rc;
        }
        record_count++;
    }

    if (algo == HYBRID_ALGO_SM4) {
        xil_printf("PROOF_SM4 PASS records=%u\r\n", (unsigned int)record_count);
    } else {
        xil_printf("PROOF_AES PASS records=%u\r\n", (unsigned int)record_count);
    }
    return 0;
}

int main(void)
{
    xil_printf("AX7020 DMA gateway hybrid perf proof image\r\n");
    xil_printf("Stage 2 SG proof contract: single-launch, %u repeats, last-descriptor polling\r\n",
               (unsigned int)HYBRID_DEFAULT_BENCH_REPEATS);
    xil_printf("PROOF_CONFIG repeats=%u ring_entries=%u usable_desc=%u\r\n",
               (unsigned int)HYBRID_DEFAULT_BENCH_REPEATS,
               (unsigned int)HYBRID_RING_ENTRY_COUNT,
               (unsigned int)HYBRID_USABLE_RING_ENTRIES);
    hybrid_print_addr_config();

    if (run_bench_for_algo(HYBRID_ALGO_AES) != 0) {
        return XST_FAILURE;
    }
    if (run_bench_for_algo(HYBRID_ALGO_SM4) != 0) {
        return XST_FAILURE;
    }

    xil_printf("DMA gateway hybrid perf proof PASS\r\n");
    return XST_SUCCESS;
}
