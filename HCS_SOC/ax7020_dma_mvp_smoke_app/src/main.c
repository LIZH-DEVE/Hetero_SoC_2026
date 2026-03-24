#include <stdint.h>
#include <string.h>

#include "xparameters.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"

#include "dma_mvp_ps_driver_ref.h"

#define DMA_CSR_BASE XPAR_DMA_SUBSYSTEM_V2_WRAPPER_0_BASEADDR

#define RING_ENTRY_COUNT 4u
#define AES_BLOCK_BYTES 16u
#define POLL_TIMEOUT_ITERS 2000000u

#define RING_DDR_ADDR      0x01000000u
#define DST_OK_DDR_ADDR    0x01002000u
#define DST_ERR_DDR_ADDR   0xF0000000u

static const uint32_t kAes128KeyWordsLswFirst[4] = {
    0x09CF4F3Cu,
    0xABF71588u,
    0x28AED2A6u,
    0x2B7E1516u,
};

static const uint32_t kPlaintextWords[4] = {
    0x3243F6A8u,
    0x885A308Du,
    0x313198A2u,
    0xE0370734u,
};

static const uint32_t kExpectedCiphertextWords[4] = {
    0x3925841Du,
    0x02DC09FBu,
    0xDC118597u,
    0x196A0B32u,
};

static dma_ring_desc_t *const g_ring = (dma_ring_desc_t *)RING_DDR_ADDR;
static uint32_t *const g_dst_ok = (uint32_t *)DST_OK_DDR_ADDR;

static void print_csw(uint32_t csw)
{
    xil_printf("  CSW=0x%08lx owner=%lu done=%lu err=%lu sts=%lu\r\n",
               (unsigned long)csw,
               (unsigned long)((csw & DMA_DESC_CSW_OWNER) != 0u),
               (unsigned long)((csw & DMA_DESC_CSW_DONE) != 0u),
               (unsigned long)((csw & DMA_DESC_CSW_ERR) != 0u),
               (unsigned long)(csw & DMA_DESC_CSW_STS_MASK));
}

static void dma_write_reg(uint32_t offset, uint32_t value)
{
    Xil_Out32((UINTPTR)(DMA_CSR_BASE + offset), value);
}

static uint32_t dma_read_reg(uint32_t offset)
{
    return Xil_In32((UINTPTR)(DMA_CSR_BASE + offset));
}

static void dma_program_aes128_encrypt(void)
{
    dma_write_reg(DMA_CSR_KEY0, kAes128KeyWordsLswFirst[0]);
    dma_write_reg(DMA_CSR_KEY1, kAes128KeyWordsLswFirst[1]);
    dma_write_reg(DMA_CSR_KEY2, kAes128KeyWordsLswFirst[2]);
    dma_write_reg(DMA_CSR_KEY3, kAes128KeyWordsLswFirst[3]);
    dma_write_reg(DMA_CSR_CTRL, DMA_CTRL_HW_INIT | DMA_CTRL_ENCRYPT);
}

static void dma_enable_ps_inject_path(void)
{
    dma_write_reg(DMA_CSR_NET_CFG0, DMA_NET_CFG_ENABLE | DMA_NET_CFG_INGRESS_INJECT);
}

static void dma_inject_words(const uint32_t *words, uint32_t word_count)
{
    uint32_t inj_ctrl;

    inj_ctrl = (word_count << 16) | 0x1u;
    dma_write_reg(DMA_CSR_INJ_CTRL, inj_ctrl);
    for (uint32_t i = 0; i < word_count; ++i) {
        dma_write_reg(DMA_CSR_INJ_DATA, words[i]);
    }
}

static int poll_csw_complete(volatile dma_ring_desc_t *desc, uint32_t *csw_out)
{
    for (uint32_t i = 0; i < POLL_TIMEOUT_ITERS; ++i) {
        Xil_DCacheInvalidateRange((INTPTR)desc, sizeof(*desc));
        int rc = dma_ring_poll_csw(desc, csw_out);
        if (rc <= 0) {
            return rc;
        }
    }
    return -3;
}

static int compare_words(const uint32_t *got, const uint32_t *expected, uint32_t word_count)
{
    for (uint32_t i = 0; i < word_count; ++i) {
        if (got[i] != expected[i]) {
            xil_printf("  mismatch[%lu]: got=0x%08lx exp=0x%08lx\r\n",
                       (unsigned long)i,
                       (unsigned long)got[i],
                       (unsigned long)expected[i]);
            return -1;
        }
    }
    return 0;
}

static void print_dma_csr_snapshot(void)
{
    xil_printf("DMA smoke image\r\n");
    xil_printf("  csr_base   = 0x%08lx\r\n", (unsigned long)DMA_CSR_BASE);
    xil_printf("  ring_base  = 0x%08lx\r\n", (unsigned long)dma_read_reg(DMA_CSR_RING_BASE));
    xil_printf("  ring_size  = 0x%08lx\r\n", (unsigned long)dma_read_reg(DMA_CSR_RING_SIZE));
    xil_printf("  sw_tail    = 0x%08lx\r\n", (unsigned long)dma_read_reg(DMA_CSR_RING_SW_TAIL));
    xil_printf("  hw_head    = 0x%08lx\r\n", (unsigned long)dma_read_reg(DMA_CSR_RING_HW_HEAD));
    xil_printf("  inj_status = 0x%08lx\r\n", (unsigned long)dma_read_reg(DMA_CSR_INJ_STATUS));
}

static int run_normal_transaction(dma_ring_ctx_t *ctx)
{
    uint32_t csw = 0u;
    int rc;

    memset((void *)g_dst_ok, 0xA5, AES_BLOCK_BYTES);
    Xil_DCacheFlushRange((INTPTR)g_dst_ok, AES_BLOCK_BYTES);

    dma_inject_words(kPlaintextWords, 4u);

    rc = dma_ring_submit(ctx, DST_OK_DDR_ADDR, AES_BLOCK_BYTES, 0u, kPlaintextWords, AES_BLOCK_BYTES);
    if (rc != 0) {
        xil_printf("normal submit failed: %d\r\n", rc);
        return -1;
    }

    rc = poll_csw_complete(&ctx->ring_base[0], &csw);
    print_csw(csw);
    if (rc != 0) {
        xil_printf("normal poll failed: %d\r\n", rc);
        return -2;
    }

    dma_ring_invalidate_result((void *)g_dst_ok, AES_BLOCK_BYTES);
    if (compare_words(g_dst_ok, kExpectedCiphertextWords, 4u) != 0) {
        xil_printf("normal payload compare failed\r\n");
        return -3;
    }

    xil_printf("normal transaction PASS\r\n");
    return 0;
}

static int run_error_transaction(dma_ring_ctx_t *ctx)
{
    uint32_t csw = 0u;
    int rc;

    dma_inject_words(kPlaintextWords, 4u);

    rc = dma_ring_submit(ctx, DST_ERR_DDR_ADDR, AES_BLOCK_BYTES, 0u, kPlaintextWords, AES_BLOCK_BYTES);
    if (rc != 0) {
        xil_printf("error submit failed: %d\r\n", rc);
        return -1;
    }

    rc = poll_csw_complete(&ctx->ring_base[1], &csw);
    print_csw(csw);
    if (rc != -2) {
        xil_printf("error transaction expected dma_ring_poll_csw=-2, got %d\r\n", rc);
        return -2;
    }
    if ((csw & DMA_DESC_CSW_ERR) == 0u) {
        xil_printf("error transaction expected ERR bit\r\n");
        return -3;
    }

    xil_printf("error transaction PASS\r\n");
    return 0;
}

int main(void)
{
    dma_ring_ctx_t ctx;
    int rc;

    memset((void *)g_ring, 0, sizeof(dma_ring_desc_t) * RING_ENTRY_COUNT);
    Xil_DCacheFlushRange((INTPTR)g_ring, sizeof(dma_ring_desc_t) * RING_ENTRY_COUNT);

    dma_ring_init(&ctx,
                  DMA_CSR_BASE,
                  g_ring,
                  RING_DDR_ADDR,
                  RING_ENTRY_COUNT);

    dma_program_aes128_encrypt();
    dma_enable_ps_inject_path();
    print_dma_csr_snapshot();

    rc = run_normal_transaction(&ctx);
    if (rc != 0) {
        xil_printf("DMA smoke FAIL at normal transaction\r\n");
        return 1;
    }

    rc = run_error_transaction(&ctx);
    if (rc != 0) {
        xil_printf("DMA smoke FAIL at error transaction\r\n");
        return 2;
    }

    xil_printf("DMA smoke PASS\r\n");
    return 0;
}
