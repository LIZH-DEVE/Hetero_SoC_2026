import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

SUBMIT_MAIN = HCS_SOC / "ax7020_dma_raw_copy_submit_diag_app" / "src" / "main.c"
SUBMIT_LSCRIPT = HCS_SOC / "ax7020_dma_raw_copy_submit_diag_app" / "src" / "lscript.ld"
SUBMIT_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_submit_diag_boot.ps1"
SUBMIT_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_submit_diag_to_sd.ps1"
SUBMIT_BOOT_BIF = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_submit_diag" / "boot.bif"


class TestDmaRawCopySubmitDiagRelease(unittest.TestCase):
    def test_submit_diag_app_contract_if_present(self):
        if not SUBMIT_MAIN.exists():
            self.skipTest(f"Submit diag app not present yet: {SUBMIT_MAIN}")

        text = SUBMIT_MAIN.read_text(encoding="ascii")
        self.assertIn("dma_hw_regs.h", text)
        self.assertIn("dma_mvp_ps_driver_ref.h", text)
        self.assertIn(".dma_desc_region", text)
        self.assertIn(".dma_src_region", text)
        self.assertIn(".dma_dst_region", text)
        self.assertIn("clear_regions(", text)
        self.assertIn("seed_raw_copy_buffers(", text)
        self.assertGreaterEqual(text.count("dma_ring_init("), 2)
        self.assertIn("dma_ring_soft_reset(", text)
        self.assertIn("dma_ring_submit_raw_copy(", text)
        self.assertNotIn("dma_ring_poll_csw(", text)
        self.assertNotIn("dma_ring_invalidate_result(", text)
        self.assertIn("RAWCOPY SUBMIT DIAG", text)
        self.assertIn("RAWCOPY_SUBMIT_STAGE REINIT_DONE", text)
        self.assertIn("RAWCOPY_SUBMIT_STAGE BEFORE_SUBMIT", text)
        self.assertIn("RAWCOPY_SUBMIT_STAGE AFTER_SUBMIT rc=", text)
        self.assertIn("RAWCOPY_SUBMIT_OK", text)
        self.assertIn("RAWCOPY_SUBMIT_HEARTBEAT", text)

    def test_submit_lscript_contract_if_present(self):
        if not SUBMIT_LSCRIPT.exists():
            self.skipTest(f"Submit diag linker script not present yet: {SUBMIT_LSCRIPT}")

        text = SUBMIT_LSCRIPT.read_text(encoding="ascii")
        self.assertIn(".dma_desc_region", text)
        self.assertIn(".dma_src_region", text)
        self.assertIn(".dma_dst_region", text)

    def test_boot_release_contract_if_files_exist(self):
        existing = [
            path for path in (SUBMIT_BUILD_BOOT, SUBMIT_DEPLOY, SUBMIT_BOOT_BIF)
            if path.exists()
        ]
        if not existing:
            self.skipTest("Submit diag boot/deploy artifacts not present yet")

        for required in (SUBMIT_BUILD_BOOT, SUBMIT_DEPLOY, SUBMIT_BOOT_BIF):
            self.assertTrue(required.exists(), f"Expected staged submit diag artifact missing: {required}")

        lines = [
            line.strip()
            for line in SUBMIT_BOOT_BIF.read_text(encoding="ascii").splitlines()
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
