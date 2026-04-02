import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
GATEWAY_C = REPO_ROOT / "HCS_SOC" / "vitis_2023_udp_gateway_ws_2" / "ax7020_udp_gateway_app" / "src" / "udp_crypto_gateway.c"
GATEWAY_H = REPO_ROOT / "HCS_SOC" / "vitis_2023_udp_gateway_ws_2" / "ax7020_udp_gateway_app" / "src" / "udp_crypto_gateway.h"


class TestUdpCryptoGatewayBackendSplit(unittest.TestCase):
    def test_public_entrypoints_remain_unchanged(self):
        text = GATEWAY_H.read_text(encoding="ascii")

        for token in (
            "void udp_crypto_gateway_early_platform_prepare(void);",
            "void udp_crypto_gateway_fix_uart_after_platform_init(void);",
            "void print_app_header(void);",
            "void udp_crypto_gateway_run_direct_smoke(unsigned case_id);",
            "int start_application(void);",
            "int transfer_data(void);",
        ):
            self.assertIn(token, text)

    def test_gateway_live_path_uses_backend_accessors(self):
        text = GATEWAY_C.read_text(encoding="ascii")

        for token in (
            "#define GATEWAY_UDP_PORT_AES 4660U",
            "#define GATEWAY_UDP_PORT_SM4 4661U",
            "#define GATEWAY_UDP_PORT_CTRL 4662U",
            "typedef struct {",
            "} gateway_mmio_backend_t;",
            "typedef gateway_mmio_backend_t gateway_backend_ops_t;",
            "static const gateway_backend_ops_t g_gateway_direct_mmio_backend = {",
            "static const gateway_backend_ops_t g_gateway_dma_probe_backend = {",
            "static const gateway_backend_ops_t *g_gateway_backend = &g_gateway_direct_mmio_backend;",
            "static uint32_t gateway_backend_read32(uint32_t offset)",
            "static void gateway_backend_write32(uint32_t offset, uint32_t value)",
            "return g_gateway_backend->read32(offset);",
            "g_gateway_backend->write32(offset, value);",
            "static void gateway_backend_select_direct_mmio(void)",
            "static void gateway_backend_select_dma_probe(void)",
            "gateway_backend_select_direct_mmio();",
            "gateway_backend_write_ctrl(",
            "gateway_backend_write_data_in(",
            "gateway_backend_read_data_out(",
        ):
            self.assertIn(token, text)

    def test_backend_capability_model_is_present(self):
        text = GATEWAY_C.read_text(encoding="ascii")

        for token in (
            "typedef enum {",
            "GATEWAY_BACKEND_KIND_DIRECT_MMIO = 0U,",
            "GATEWAY_BACKEND_KIND_DMA_PROBE = 1U,",
            "typedef uint32_t gateway_backend_caps_t;",
            "#define GATEWAY_BACKEND_CAP_CRYPTO_SYNC 0x00000001U",
            "#define GATEWAY_BACKEND_CAP_DMA_PROBE    0x00000002U",
            "typedef struct {",
            "gateway_backend_kind_t kind;",
            "gateway_backend_caps_t caps;",
            "int (*probe_init)(void);",
            "int (*probe_submit_frame)(const uint8_t *frame, uint16_t frame_len);",
            "int (*probe_poll_done)(void);",
            "int (*probe_read_result)(uint16_t *actual_len, uint32_t *status);",
            "void (*probe_reset)(void);",
            "static const gateway_backend_ops_t g_gateway_direct_mmio_backend = {",
            "static const gateway_backend_ops_t g_gateway_dma_probe_backend = {",
            "static const gateway_backend_ops_t *g_gateway_backend = &g_gateway_direct_mmio_backend;",
            "static void gateway_backend_select_direct_mmio(void)",
            "static void gateway_backend_select_dma_probe(void)",
            "#define GATEWAY_BACKEND_ERR_NOT_SUPPORTED (-95)",
            "static int gateway_backend_require(gateway_backend_caps_t caps, const char *op_name)",
        ):
            self.assertIn(token, text)

    def test_crypto_sync_paths_fail_closed_without_capability(self):
        text = GATEWAY_C.read_text(encoding="ascii")

        for token in (
            'gateway_backend_require(GATEWAY_BACKEND_CAP_CRYPTO_SYNC, "encrypt_sync")',
            'gateway_backend_require(GATEWAY_BACKEND_CAP_CRYPTO_SYNC, "bench")',
            'udp_crypto_gateway: backend op=%s not supported kind=%u caps=0x%08lx need=0x%08lx',
            "int udp_crypto_gateway_run_direct_smoke_checked(unsigned case_id)",
            "int udp_crypto_gateway_run_backend_split_smoke_checked(void)",
            "gateway_backend_select_dma_probe();",
            "gateway_backend_select_direct_mmio();",
        ):
            self.assertIn(token, text)

    def test_live_paths_do_not_select_dma_probe_backend(self):
        text = GATEWAY_C.read_text(encoding="ascii")

        start_idx = text.index("int start_application(void)")
        transfer_idx = text.index("int transfer_data(void)")
        live_slice = text[start_idx:transfer_idx]

        for token in (
            "gateway_backend_select_dma_probe()",
            "GATEWAY_BACKEND_KIND_DMA_PROBE",
            "GATEWAY_BACKEND_CAP_DMA_PROBE",
            "probe_submit_frame(",
            "probe_read_result(",
            "probe_reset(",
        ):
            self.assertNotIn(token, live_slice)


if __name__ == "__main__":
    unittest.main()
