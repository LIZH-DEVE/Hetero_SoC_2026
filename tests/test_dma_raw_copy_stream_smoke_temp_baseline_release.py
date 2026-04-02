import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

TEMP_BUILD_BOOT = HCS_SOC / "build_ax7020_design1fsbl_stream_smoke_app_boot.ps1"
TEMP_DEPLOY = HCS_SOC / "deploy_ax7020_design1fsbl_stream_smoke_app_to_sd.ps1"
TEMP_RELEASE_DIR = HCS_SOC / "sd_boot" / "ax7020_design1fsbl_stream_smoke_app"
TEMP_BOOT_BIF = TEMP_RELEASE_DIR / "boot.bif"
TEMP_README = TEMP_RELEASE_DIR / "readme.txt"
TEMP_BOOTGEN_READ = TEMP_RELEASE_DIR / "bootgen_read.txt"
BOARD_BASELINES = HCS_SOC / "sd_boot" / "AX7020_REPO_BOARD_BASELINES.md"
FSBL_MATRIX = HCS_SOC / "STREAM_SMOKE_FSBL_MATRIX.md"


class TestDmaRawCopyStreamSmokeTempBaselineRelease(unittest.TestCase):
    def test_temp_baseline_assets_exist(self):
        for required in (
            TEMP_BUILD_BOOT,
            TEMP_DEPLOY,
            TEMP_BOOT_BIF,
            TEMP_README,
            TEMP_BOOTGEN_READ,
            BOARD_BASELINES,
            FSBL_MATRIX,
        ):
            self.assertTrue(required.exists(), f"Expected temp baseline asset missing: {required}")

    def test_temp_release_contract(self):
        build_text = TEMP_BUILD_BOOT.read_text(encoding="ascii")
        deploy_text = TEMP_DEPLOY.read_text(encoding="ascii")
        readme_text = TEMP_README.read_text(encoding="ascii")

        self.assertIn("Temporary board-proven Phase 3 baseline", readme_text)
        self.assertIn("design_1 FSBL", readme_text)
        self.assertIn("stream_smoke_dma_wrapper.bit", readme_text)
        self.assertIn("DMA stream smoke PASS", readme_text)
        self.assertIn("temporary board-proven Phase 3 baseline", deploy_text)
        self.assertIn("DMA stream smoke PASS", deploy_text)
        self.assertIn("stream_smoke_dma_wrapper.bit", build_text)
        self.assertIn("ax7020_dma_raw_copy_stream_smoke_app.elf", build_text)

    def test_board_baseline_doc_and_matrix(self):
        board_text = BOARD_BASELINES.read_text(encoding="utf-8")
        matrix_text = FSBL_MATRIX.read_text(encoding="utf-8")

        self.assertIn("4. `ax7020_dma_raw_copy_mvp`", board_text)
        self.assertIn("5. `ax7020_dma_raw_copy_stream_smoke`", board_text)
        self.assertIn("6. `ax7020_dma_gateway_hybrid_smoke`", board_text)
        self.assertIn("fallback Phase 3 baseline", board_text)
        self.assertIn("board-proven dedicated Phase 3 stream-smoke image", board_text)
        self.assertIn("dedicated FSBL trace diagnostic image", board_text)
        self.assertIn("dedicated FSBL no-post-config diagnostic image", board_text)
        self.assertIn("diagnostic only; not part of the normal board-test order", board_text)

        self.assertIn("stream-smoke FSBL + no-bit + stream-smoke app", matrix_text)
        self.assertIn("design1 FSBL + stream-smoke bit + design1 UART app", matrix_text)
        self.assertIn("design1 FSBL + stream-smoke bit + stream-smoke app", matrix_text)
        self.assertIn("stream-smoke FSBL + stream-smoke bit + stream-smoke app", matrix_text)
        self.assertIn("FSBL_DIAG AFTER_PS7_INIT", matrix_text)
        self.assertIn("FSBL no-post-config image", matrix_text)
        self.assertIn("Current strongest concrete delta", matrix_text)
        self.assertIn("PCW_USE_S_AXI_HP0 = 0", matrix_text)
        self.assertIn("PCW_USE_S_AXI_HP0 = 1", matrix_text)
        self.assertIn("CRYPTO_ACCEL_AXI_0", matrix_text)
        self.assertIn("DMA_STREAM_SMOKE_SUBSYSTEM_0", matrix_text)
        self.assertIn("Gateway stays blocked", matrix_text)


if __name__ == "__main__":
    unittest.main()
