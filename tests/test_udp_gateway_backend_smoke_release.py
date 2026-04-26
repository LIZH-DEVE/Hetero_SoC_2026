import pathlib
import re
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"
GATEWAY_C = HCS_SOC / "vitis_2023_udp_gateway_ws_2" / "ax7020_udp_gateway_app" / "src" / "udp_crypto_gateway.c"

APP_MAIN = HCS_SOC / "ax7020_udp_gateway_backend_smoke_app" / "src" / "main.c"
APP_LSCRIPT = HCS_SOC / "ax7020_udp_gateway_backend_smoke_app" / "src" / "lscript.ld"
BUILD_APP = HCS_SOC / "build_ax7020_udp_gateway_backend_smoke_app.ps1"
BUILD_BOOT = HCS_SOC / "build_ax7020_udp_gateway_backend_smoke_boot.ps1"
DEPLOY = HCS_SOC / "deploy_ax7020_udp_gateway_backend_smoke_to_sd.ps1"
RELEASE_DIR = HCS_SOC / "sd_boot" / "ax7020_udp_gateway_backend_smoke"
BOOT_BIN = RELEASE_DIR / "BOOT.BIN"
BOOT_BIF = RELEASE_DIR / "boot.bif"
READ_ME = RELEASE_DIR / "readme.txt"
BOOTGEN_READ = RELEASE_DIR / "bootgen_read.txt"
STAGED_FSBL = RELEASE_DIR / "fsbl.elf"
STAGED_BIT = RELEASE_DIR / "dma_gateway_hybrid_wrapper.bit"
STAGED_APP = RELEASE_DIR / "ax7020_udp_gateway_backend_smoke_app.elf"


def _extract_boot_payload(boot_bif: pathlib.Path) -> list[str]:
    lines = [
        line.strip()
        for line in boot_bif.read_text(encoding="ascii").splitlines()
        if line.strip() and not line.strip().startswith("//")
    ]
    return lines[2:-1]


def _extract_function_block(text: str, signature: str) -> str:
    match = re.search(re.escape(signature), text)
    if match is None:
        raise AssertionError(f"Function signature not found: {signature}")

    open_brace = text.find("{", match.end())
    if open_brace < 0:
        raise AssertionError(f"Opening brace not found for function: {signature}")

    depth = 0
    for index in range(open_brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[match.start(): index + 1]

    raise AssertionError(f"Closing brace not found for function: {signature}")


class TestUdpGatewayBackendSmokeRelease(unittest.TestCase):
    def test_backend_smoke_assets_exist(self):
        for required in (
            APP_MAIN,
            APP_LSCRIPT,
            BUILD_APP,
            BUILD_BOOT,
            DEPLOY,
            RELEASE_DIR,
            BOOT_BIN,
            BOOT_BIF,
            READ_ME,
            BOOTGEN_READ,
            STAGED_FSBL,
            STAGED_BIT,
            STAGED_APP,
        ):
            self.assertTrue(required.exists(), f"Expected backend smoke asset missing: {required}")

    def test_backend_smoke_app_contract(self):
        text = APP_MAIN.read_text(encoding="ascii")

        for token in (
            "static int run_direct_backend_regression(void)",
            "static int run_dma_probe_smoke(void)",
            "DIRECT_BACKEND PASS",
            'run_dma_probe_case("EXACT_FIT"',
            'run_dma_probe_case("SHORT"',
            'run_dma_probe_case("OVERFLOW"',
            "DMA_PROBE WRONG_PORT PASS count=%u",
            "DMA_PROBE UNALIGNED_REJECT PASS rc=%d",
            "DMA_PROBE PASS",
            "UDP gateway backend smoke PASS",
            "udp_crypto_gateway_run_backend_split_smoke_checked(",
            "dma_ring_submit_stream(",
            "WRAP_REG_DROP_WRONG_PORT_COUNT",
            "WRAP_REG_DROP_UNALIGNED_COUNT",
            "return -6;",
        ):
            self.assertIn(token, text)

        reject_idx = text.index("return -6;")
        inj_idx = text.index("wrap_write32(WRAP_REG_INJ_DATA, frame_words[word_idx]);")
        doorbell_idx = text.index("dma_ring_submit_stream(")
        self.assertLess(reject_idx, inj_idx)
        self.assertLess(reject_idx, doorbell_idx)

        direct_block = _extract_function_block(text, "static int run_direct_backend_regression(void)")
        probe_block = _extract_function_block(text, "static int run_dma_probe_smoke(void)")
        self.assertIn("DIRECT_BACKEND PASS", direct_block)
        self.assertIn("DMA_PROBE PASS", probe_block)
        self.assertIn("udp_crypto_gateway_run_backend_split_smoke_checked();", direct_block)

        gateway_text = GATEWAY_C.read_text(encoding="ascii")
        self.assertIn("int udp_crypto_gateway_run_direct_smoke_checked(unsigned case_id)", gateway_text)
        self.assertIn("int udp_crypto_gateway_run_backend_split_smoke_checked(void)", gateway_text)
        self.assertIn("GATEWAY_BACKEND_ERR_NOT_SUPPORTED", gateway_text)
        self.assertIn('gateway_backend_require(GATEWAY_BACKEND_CAP_CRYPTO_SYNC, "encrypt_sync")', gateway_text)

    def test_backend_smoke_release_contract(self):
        build_app = BUILD_APP.read_text(encoding="ascii")
        build_boot = BUILD_BOOT.read_text(encoding="ascii")
        deploy = DEPLOY.read_text(encoding="ascii")
        readme = READ_ME.read_text(encoding="ascii")

        for token in (
            "ax7020_udp_gateway_backend_smoke_app",
            "UDP_GATEWAY_SMOKE_ONLY_BUILD",
            "udp_crypto_gateway.c",
            "dma_gateway_hybrid_wrapper.xsa",
            "dma_gateway_hybrid_wrapper.bit",
            "ax7020_udp_gateway_backend_smoke_app.elf",
            "ax7020_udp_gateway_backend_smoke",
        ):
            self.assertIn(token, build_app + build_boot)
        self.assertIn("bootgen -read", build_boot)

        self.assertIn('Join-Path $workspace "sd_boot\\ax7020_udp_gateway_backend_smoke"', deploy)
        self.assertIn('Join-Path $sdDriveRoot "BOOT.BIN"', deploy)

        for token in (
            "UDP gateway backend smoke image",
            "Phase B backend split smoke image",
            "C85DDC649E523FB03863CB2B9C842E434E173EE546BDB1FCADC56EB467507AD3",
            "Expected UART pass criteria:",
            "DIRECT_BACKEND PASS",
            "DMA_PROBE EXACT_FIT PASS",
            "DMA_PROBE SHORT PASS",
            "DMA_PROBE OVERFLOW PASS",
            "DMA_PROBE WRONG_PORT PASS",
            "DMA_PROBE UNALIGNED_REJECT PASS",
            "DMA_PROBE PASS",
            "UDP gateway backend smoke PASS",
        ):
            self.assertIn(token, readme)

    def test_backend_smoke_boot_image_is_three_stage(self):
        payload = _extract_boot_payload(BOOT_BIF)
        bootgen_read = BOOTGEN_READ.read_text(encoding="ascii")

        self.assertEqual(len(payload), 3)
        self.assertTrue(payload[0].startswith("[bootloader] "))
        self.assertIn("dma_gateway_hybrid_wrapper.bit", payload[1])
        self.assertIn("ax7020_udp_gateway_backend_smoke_app.elf", payload[2])
        self.assertIn("fsbl.elf", bootgen_read)
        self.assertIn("dma_gateway_hybrid_wrapper.bit", bootgen_read)
        self.assertIn("ax7020_udp_gateway_backend_smoke_app.elf", bootgen_read)


if __name__ == "__main__":
    unittest.main()
