import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

REINIT_MAIN = HCS_SOC / "ax7020_dma_raw_copy_reinit_after_reset_diag_app" / "src" / "main.c"
REINIT_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_reinit_after_reset_diag_boot.ps1"
REINIT_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_reinit_after_reset_diag_to_sd.ps1"
REINIT_BOOT_BIF = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_reinit_after_reset_diag" / "boot.bif"


class TestDmaRawCopyReinitAfterResetDiagRelease(unittest.TestCase):
    def test_reinit_after_reset_diag_app_contract_if_present(self):
        if not REINIT_MAIN.exists():
            self.skipTest(f"Reinit-after-reset diag app not present yet: {REINIT_MAIN}")

        text = REINIT_MAIN.read_text(encoding="ascii")
        self.assertIn("dma_hw_regs.h", text)
        self.assertIn("dma_mvp_ps_driver_ref.h", text)
        self.assertGreaterEqual(text.count("dma_ring_init("), 2)
        self.assertIn("dma_ring_soft_reset(", text)
        self.assertNotIn("dma_ring_submit(", text)
        self.assertNotIn("dma_ring_submit_raw_copy(", text)
        self.assertNotIn("dma_ring_poll_csw(", text)
        self.assertIn("RAWCOPY REINIT AFTER RESET DIAG", text)
        self.assertIn("RAWCOPY_REINIT_AFTER_RESET_STAGE BEFORE_REINIT", text)
        self.assertIn("RAWCOPY_REINIT_AFTER_RESET_STAGE AFTER_REINIT", text)
        self.assertIn("RAWCOPY_REINIT_AFTER_RESET_OK", text)
        self.assertIn("RAWCOPY_REINIT_HEARTBEAT", text)

    def test_boot_release_contract_if_files_exist(self):
        existing = [
            path for path in (REINIT_BUILD_BOOT, REINIT_DEPLOY, REINIT_BOOT_BIF)
            if path.exists()
        ]
        if not existing:
            self.skipTest("Reinit-after-reset diag boot/deploy artifacts not present yet")

        for required in (REINIT_BUILD_BOOT, REINIT_DEPLOY, REINIT_BOOT_BIF):
            self.assertTrue(required.exists(), f"Expected staged reinit-after-reset diag artifact missing: {required}")

        lines = [
            line.strip()
            for line in REINIT_BOOT_BIF.read_text(encoding="ascii").splitlines()
            if line.strip() and not line.strip().startswith("//")
        ]
        self.assertEqual(lines[0], "the_ROM_image:")
        self.assertEqual(lines[1], "{")
        self.assertEqual(lines[-1], "}")
        payload = lines[2:-1]
        self.assertEqual(len(payload), 3)
        self.assertTrue(payload[0].startswith("[bootloader] "))
        self.assertTrue(payload[1].endswith(".bit"))
        self.assertTrue(payload[2].endswith(".elf"))


if __name__ == "__main__":
    unittest.main()
