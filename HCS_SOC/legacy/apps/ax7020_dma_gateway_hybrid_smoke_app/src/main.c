#include <stdint.h>
#include <string.h>

#include "sleep.h"
#include "xparameters.h"
#include "xstatus.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xuartps.h"

#include "dma_hw_regs.h"
#include "dma_mvp_ps_driver_ref.h"

#define HYBRID_CTRL_BASEADDR 0x40000000u
#define HYBRID_DMA_BASEADDR 0x40001000u

#define WRAP_REG_NET_CFG0 0x90u
#define WRAP_REG_NET_LOCAL_IP 0x94u
#define WRAP_REG_NET_LOCAL_MAC_LO 0x98u
#define WRAP_REG_NET_LOCAL_MAC_HI 0x9Cu
#define WRAP_REG_INJ_CTRL 0xA0u
#define WRAP_REG_INJ_DATA 0xA4u
#define WRAP_REG_INJ_STATUS 0xA8u
#define WRAP_REG_TXCAP_CTRL 0xACu
#define WRAP_REG_TXCAP_STATUS 0xB0u
#define WRAP_REG_TXCAP_DATA 0xB4u
#define WRAP_REG_NETDBG_STATUS 0xB8u
#define WRAP_REG_NET_APPLIED_CFG0 0xBCu
#define WRAP_REG_NET_APPLIED_LOCAL_IP 0xC0u
#define WRAP_REG_NET_APPLIED_LOCAL_MAC_LO 0xC4u
#define WRAP_REG_NET_APPLIED_LOCAL_MAC_HI 0xC8u
#define WRAP_REG_DROP_WRONG_PORT_COUNT 0xCCu
#define WRAP_REG_DROP_UNALIGNED_COUNT 0xD0u

#define NET_CFG_ENABLE 0x00000001u
#define NET_CFG_INJECT_SEL 0x00000002u
#define NET_CFG_ARP_ENABLE 0x00000004u

#define HYBRID_LOCAL_IP 0xC0A80114u
#define HYBRID_LOCAL_MAC_LO 0x35000120u
#define HYBRID_LOCAL_MAC_HI 0x0000020Au

#define HYBRID_RING_ENTRY_COUNT 2u
#define HYBRID_MAX_PAYLOAD_BYTES 1024u
#define HYBRID_SHORT_BYTES 64u
#define HYBRID_OVERFLOW_BYTES 128u
#define HYBRID_OVERFLOW_CAPACITY 64u
#define HYBRID_WORD_BYTES 4u
#define HYBRID_POLL_TIMEOUT 3000000u

#define HYBRID_PORT_AES 4660u
#define HYBRID_PORT_SM4 4661u
#define HYBRID_PORT_CTRL 4662u
#define HYBRID_PORT_WRONG 4663u

typedef struct {
    dma_ring_desc_t ring[HYBRID_RING_ENTRY_COUNT];
    uint8_t guard[DMA_CACHELINE_BYTES];
} hybrid_desc_region_t;

typedef struct {
    uint32_t words[HYBRID_MAX_PAYLOAD_BYTES / HYBRID_WORD_BYTES];
    uint8_t guard[DMA_CACHELINE_BYTES];
} hybrid_buffer_region_t;

static hybrid_desc_region_t g_desc_region
    __attribute__((aligned(DMA_ALIGNMENT_BYTES), section(".hybrid_desc_region")));
static hybrid_buffer_region_t g_dst_region
    __attribute__((aligned(DMA_ALIGNMENT_BYTES), section(".hybrid_dst_region")));
static XUartPs g_uart;

static inline void wrap_write32(uint32_t offset, uint32_t value)
{
    Xil_Out32((UINTPTR)(HYBRID_CTRL_BASEADDR + offset), value);
}

static inline uint32_t wrap_read32(uint32_t offset)
{
    return Xil_In32((UINTPTR)(HYBRID_CTRL_BASEADDR + offset));
}

static uint32_t make_pattern_word(uint32_t word_idx)
{
    uint32_t base = word_idx * 4u;
    return ((base + 0u) & 0xFFu) |
           (((base + 1u) & 0xFFu) << 8) |
           (((base + 2u) & 0xFFu) << 16) |
           (((base + 3u) & 0xFFu) << 24);
}

static int uart1_init_115200(void)
{
    XUartPs_Config *config;
    int status;

    config = XUartPs_LookupConfig(XPAR_XUARTPS_0_DEVICE_ID);
    if (config == 0) {
        return XST_FAILURE;
    }

    status = XUartPs_CfgInitialize(&g_uart, config, config->BaseAddress);
    if (status != XST_SUCCESS) {
        return status;
    }

    return XUartPs_SetBaudRate(&g_uart, 115200u);
}

static void clear_regions(void)
{
    memset(&g_desc_region, 0, sizeof(g_desc_region));
    memset(&g_dst_region, 0xA5, sizeof(g_dst_region));
}

static void prepare_ring(dma_ring_ctx_t *ctx)
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

static int wait_for_done_csw(volatile dma_ring_desc_t *desc, uint32_t *csw_out)
{
    uint32_t i;

    for (i = 0; i < HYBRID_POLL_TIMEOUT; ++i) {
        uint32_t csw;

        Xil_DCacheInvalidateRange((INTPTR)desc, sizeof(*desc));
        DATA_SYNC;
        csw = desc->csw;
        if (((csw & DMA_DESC_CSW_OWNER) == 0u) && ((csw & DMA_DESC_CSW_DONE) != 0u)) {
            if (csw_out != 0) {
                *csw_out = csw;
            }
            return 0;
        }
    }

    return -1;
}

static int wait_for_counter_increment(uint32_t offset, uint32_t before_value)
{
    uint32_t i;

    for (i = 0; i < HYBRID_POLL_TIMEOUT; ++i) {
        if (wrap_read32(offset) == (before_value + 1u)) {
            return 0;
        }
    }

    return -1;
}

static void configure_hybrid_control(void)
{
    wrap_write32(WRAP_REG_NET_CFG0, NET_CFG_ENABLE | NET_CFG_INJECT_SEL | NET_CFG_ARP_ENABLE);
    wrap_write32(WRAP_REG_NET_LOCAL_IP, HYBRID_LOCAL_IP);
    wrap_write32(WRAP_REG_NET_LOCAL_MAC_LO, HYBRID_LOCAL_MAC_LO);
    wrap_write32(WRAP_REG_NET_LOCAL_MAC_HI, HYBRID_LOCAL_MAC_HI);
    wrap_write32(WRAP_REG_INJ_CTRL, 1u);
    wrap_write32(WRAP_REG_TXCAP_CTRL, 1u);
}

static int hybrid_inject_udp_frame(uint16_t dst_port, uint16_t payload_len_bytes)
{
    uint32_t frame_words[11 + (HYBRID_MAX_PAYLOAD_BYTES / HYBRID_WORD_BYTES)];
    uint32_t payload_words;
    uint32_t frame_word_count;
    uint32_t word_idx;

    if ((payload_len_bytes == 0u) || (payload_len_bytes > HYBRID_MAX_PAYLOAD_BYTES)) {
        return -5;
    }
    if ((payload_len_bytes & (HYBRID_WORD_BYTES - 1u)) != 0u) {
        return -6;
    }

    payload_words = payload_len_bytes / HYBRID_WORD_BYTES;
    frame_word_count = 11u + payload_words;
    memset(frame_words, 0, sizeof(frame_words));

    frame_words[0] = 0x020ABBCCu;
    frame_words[1] = 0xDDEE020Au;
    frame_words[2] = HYBRID_LOCAL_MAC_LO;
    frame_words[3] = 0x08000000u;
    frame_words[4] = (((uint32_t)(20u + 8u + payload_len_bytes)) << 16) | 0x0005u;
    frame_words[5] = 0x00000000u;
    frame_words[6] = 0x40110000u;
    frame_words[7] = 0xC0A80101u;
    frame_words[8] = HYBRID_LOCAL_IP;
    frame_words[9] = ((uint32_t)dst_port << 16) | 0x1234u;
    frame_words[10] = ((uint32_t)0u << 16) | (uint32_t)(payload_len_bytes + 8u);

    for (word_idx = 0; word_idx < payload_words; ++word_idx) {
        frame_words[11u + word_idx] = make_pattern_word(word_idx);
    }

    wrap_write32(WRAP_REG_INJ_CTRL, 1u);
    DATA_SYNC;
    usleep(1000U);
    wrap_write32(WRAP_REG_INJ_CTRL, ((uint32_t)frame_word_count << 16));
    DATA_SYNC;
    for (word_idx = 0; word_idx < frame_word_count; ++word_idx) {
        wrap_write32(WRAP_REG_INJ_DATA, frame_words[word_idx]);
    }
    DATA_SYNC;
    return 0;
}

static int verify_payload_words(uint32_t expected_bytes)
{
    uint32_t word_idx;
    uint32_t expected_words = expected_bytes / HYBRID_WORD_BYTES;

    dma_ring_invalidate_result(g_dst_region.words, expected_bytes);
    for (word_idx = 0; word_idx < expected_words; ++word_idx) {
        if (g_dst_region.words[word_idx] != make_pattern_word(word_idx)) {
            xil_printf("  payload mismatch[%u]: got=0x%08x exp=0x%08x\r\n",
                       (unsigned int)word_idx,
                       (unsigned int)g_dst_region.words[word_idx],
                       (unsigned int)make_pattern_word(word_idx));
            return -1;
        }
    }
    return 0;
}

static const char *csw_status_to_string(uint32_t csw)
{
    switch (csw & DMA_DESC_CSW_STS_MASK) {
    case DMA_DESC_CSW_STS_OK:
        return "OK";
    case DMA_DESC_CSW_STS_AXI_RESP:
        return "AXI_RESP";
    case DMA_DESC_CSW_STS_OVERFLOW_OR_MISSING_TLAST:
        return "OVERFLOW_OR_MISSING_TLAST";
    case DMA_DESC_CSW_STS_INTERNAL:
        return "INTERNAL";
    default:
        return "UNKNOWN";
    }
}

static int run_accept_case(const char *stage_name,
                           uint16_t dst_port,
                           uint32_t capacity_bytes,
                           uint32_t packet_len_bytes,
                           uint32_t expected_actual_len,
                           uint32_t expect_err,
                           uint32_t expect_sts)
{
    dma_ring_ctx_t ctx;
    uint32_t csw = 0u;
    uint32_t actual_len;
    int rc;

    clear_regions();
    prepare_ring(&ctx);

    rc = dma_ring_submit_stream(&ctx,
                                (uint32_t)(uintptr_t)g_dst_region.words,
                                capacity_bytes,
                                0,
                                0);
    if (rc != 0) {
        xil_printf("%s submit rc=%d\r\n", stage_name, rc);
        return -10;
    }

    xil_printf("STREAM_STAGE %s PREP capacity=%u packet_len=%u\r\n",
               stage_name,
               (unsigned int)capacity_bytes,
               (unsigned int)packet_len_bytes);

    rc = hybrid_inject_udp_frame(dst_port, (uint16_t)packet_len_bytes);
    if (rc != 0) {
        xil_printf("%s inject rc=%d\r\n", stage_name, rc);
        return -11;
    }

    rc = wait_for_done_csw(&g_desc_region.ring[0], &csw);
    if (rc != 0) {
        xil_printf("%s csw timeout\r\n", stage_name);
        return -12;
    }

    actual_len = dma_ring_read_actual_len(&g_desc_region.ring[0]);
    if (actual_len != expected_actual_len) {
        xil_printf("%s actual_len mismatch exp=%u got=%u\r\n",
                   stage_name,
                   (unsigned int)expected_actual_len,
                   (unsigned int)actual_len);
        return -13;
    }
    if (((csw & DMA_DESC_CSW_ERR) != 0u) != (expect_err != 0u)) {
        xil_printf("%s err flag mismatch csw=0x%08x\r\n", stage_name, (unsigned int)csw);
        return -14;
    }
    if ((csw & DMA_DESC_CSW_STS_MASK) != expect_sts) {
        xil_printf("%s sts mismatch exp=%s got=%s\r\n",
                   stage_name,
                   csw_status_to_string(expect_sts),
                   csw_status_to_string(csw));
        return -15;
    }
    if (verify_payload_words(expected_actual_len) != 0) {
        return -16;
    }

    xil_printf("STREAM_STAGE %s PASS actual_len=%u\r\n",
               stage_name,
               (unsigned int)actual_len);
    return 0;
}

static int run_wrong_port_case(void)
{
    dma_ring_ctx_t ctx;
    uint32_t before_drop;
    uint16_t before_hw_head;
    int rc;

    clear_regions();
    prepare_ring(&ctx);
    before_drop = wrap_read32(WRAP_REG_DROP_WRONG_PORT_COUNT);
    before_hw_head = dma_ring_get_hw_head(&ctx);

    rc = hybrid_inject_udp_frame(HYBRID_PORT_WRONG, HYBRID_SHORT_BYTES);
    if (rc != 0) {
        return -1;
    }
    if (wait_for_counter_increment(WRAP_REG_DROP_WRONG_PORT_COUNT, before_drop) != 0) {
        return -2;
    }
    if (dma_ring_get_hw_head(&ctx) != before_hw_head || ctx.sw_tail != 0u) {
        return -3;
    }

    xil_printf("WRONG_PORT PASS count=%u\r\n",
               (unsigned int)wrap_read32(WRAP_REG_DROP_WRONG_PORT_COUNT));
    return 0;
}

static int run_unaligned_reject_case(void)
{
    dma_ring_ctx_t ctx;
    uint32_t before_drop;
    uint16_t before_hw_head;
    int rc;

    clear_regions();
    prepare_ring(&ctx);
    before_drop = wrap_read32(WRAP_REG_DROP_UNALIGNED_COUNT);
    before_hw_head = dma_ring_get_hw_head(&ctx);

    rc = hybrid_inject_udp_frame(HYBRID_PORT_AES, 66u);
    if (rc != -6) {
        return -1;
    }
    if (wrap_read32(WRAP_REG_DROP_UNALIGNED_COUNT) != before_drop) {
        return -2;
    }
    if (dma_ring_get_hw_head(&ctx) != before_hw_head || ctx.sw_tail != 0u) {
        return -3;
    }

    xil_printf("UNALIGNED_REJECT PASS rc=%d\r\n", rc);
    return 0;
}

int main(void)
{
    int rc;

    if (uart1_init_115200() != XST_SUCCESS) {
        for (;;) {
        }
    }

    configure_hybrid_control();

    xil_printf("DMA gateway hybrid smoke image\r\n");
    xil_printf("  ctrl_base    = 0x%08x\r\n", (unsigned int)HYBRID_CTRL_BASEADDR);
    xil_printf("  dma_base     = 0x%08x\r\n", (unsigned int)HYBRID_DMA_BASEADDR);
    xil_printf("  drop_wrong   = 0x%02x\r\n", (unsigned int)WRAP_REG_DROP_WRONG_PORT_COUNT);
    xil_printf("  drop_unalign = 0x%02x\r\n", (unsigned int)WRAP_REG_DROP_UNALIGNED_COUNT);

    rc = run_accept_case("EXACT_FIT",
                         HYBRID_PORT_AES,
                         1024u,
                         1024u,
                         1024u,
                         0u,
                         DMA_DESC_CSW_STS_OK);
    if (rc != 0) {
        xil_printf("EXACT_FIT FAIL rc=%d\r\n", rc);
        xil_printf("DMA gateway hybrid smoke FAIL\r\n");
        return 1;
    }

    rc = run_accept_case("SHORT",
                         HYBRID_PORT_SM4,
                         1024u,
                         HYBRID_SHORT_BYTES,
                         HYBRID_SHORT_BYTES,
                         0u,
                         DMA_DESC_CSW_STS_OK);
    if (rc != 0) {
        xil_printf("SHORT FAIL rc=%d\r\n", rc);
        xil_printf("DMA gateway hybrid smoke FAIL\r\n");
        return 2;
    }

    rc = run_accept_case("OVERFLOW",
                         HYBRID_PORT_AES,
                         HYBRID_OVERFLOW_CAPACITY,
                         HYBRID_OVERFLOW_BYTES,
                         HYBRID_OVERFLOW_CAPACITY,
                         1u,
                         DMA_DESC_CSW_STS_OVERFLOW_OR_MISSING_TLAST);
    if (rc != 0) {
        xil_printf("OVERFLOW FAIL rc=%d\r\n", rc);
        xil_printf("DMA gateway hybrid smoke FAIL\r\n");
        return 3;
    }

    rc = run_wrong_port_case();
    if (rc != 0) {
        xil_printf("WRONG_PORT FAIL rc=%d\r\n", rc);
        xil_printf("DMA gateway hybrid smoke FAIL\r\n");
        return 4;
    }

    rc = run_unaligned_reject_case();
    if (rc != 0) {
        xil_printf("UNALIGNED_REJECT FAIL rc=%d\r\n", rc);
        xil_printf("DMA gateway hybrid smoke FAIL\r\n");
        return 5;
    }

    xil_printf("DMA gateway hybrid smoke PASS\r\n");
    return 0;
}
