import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

SOFT_RESET_MAIN = HCS_SOC / "ax7020_dma_raw_copy_soft_reset_diag_app" / "src" / "main.c"
SOFT_RESET_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_soft_reset_diag_boot.ps1"
SOFT_RESET_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_soft_reset_diag_to_sd.ps1"
SOFT_RESET_BOOT_BIF = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_soft_reset_diag" / "boot.bif"


class TestDmaRawCopySoftResetDiagRelease(unittest.TestCase):
    def test_soft_reset_diag_app_contract_if_present(self):
        if not SOFT_RESET_MAIN.exists():
            self.skipTest(f"Soft-reset diag app not present yet: {SOFT_RESET_MAIN}")

        text = SOFT_RESET_MAIN.read_text(encoding="ascii")
        self.assertIn("dma_hw_regs.h", text)
        self.assertIn("dma_mvp_ps_driver_ref.h", text)
        self.assertIn("dma_ring_init(", text)
        self.assertIn("dma_ring_soft_reset(", text)
        self.assertNotIn("dma_ring_submit(", text)
        self.assertNotIn("dma_ring_submit_raw_copy(", text)
        self.assertNotIn("dma_ring_poll_csw(", text)
        self.assertIn("RAWCOPY SOFT RESET DIAG", text)
        self.assertIn("RAWCOPY_SOFT_RESET_STAGE BEFORE_SOFT_RESET", text)
        self.assertIn("RAWCOPY_SOFT_RESET_STAGE AFTER_SOFT_RESET", text)
        self.assertIn("RAWCOPY_SOFT_RESET_OK", text)
        self.assertIn("RAWCOPY_SOFT_RESET_HEARTBEAT", text)

    def test_boot_release_contract_if_files_exist(self):
        existing = [
            path for path in (SOFT_RESET_BUILD_BOOT, SOFT_RESET_DEPLOY, SOFT_RESET_BOOT_BIF)
            if path.exists()
        ]
        if not existing:
            self.skipTest("Soft-reset diag boot/deploy artifacts not present yet")

        for required in (SOFT_RESET_BUILD_BOOT, SOFT_RESET_DEPLOY, SOFT_RESET_BOOT_BIF):
            self.assertTrue(required.exists(), f"Expected staged soft-reset diag artifact missing: {required}")

        lines = [
            line.strip()
            for line in SOFT_RESET_BOOT_BIF.read_text(encoding="ascii").splitlines()
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
