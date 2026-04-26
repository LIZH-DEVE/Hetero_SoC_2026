import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

DIAG_MAIN = HCS_SOC / "ax7020_dma_raw_copy_invalidate_compare_diag_app" / "src" / "main.c"
DIAG_LSCRIPT = HCS_SOC / "ax7020_dma_raw_copy_invalidate_compare_diag_app" / "src" / "lscript.ld"
DIAG_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_invalidate_compare_diag_boot.ps1"
DIAG_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_invalidate_compare_diag_to_sd.ps1"
DIAG_BOOT_BIF = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_invalidate_compare_diag" / "boot.bif"


class TestDmaRawCopyInvalidateCompareDiagRelease(unittest.TestCase):
    def test_invalidate_compare_diag_app_contract_if_present(self):
        if not DIAG_MAIN.exists():
            self.skipTest(f"Invalidate/compare diag app not present yet: {DIAG_MAIN}")

        text = DIAG_MAIN.read_text(encoding="ascii")
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
        self.assertIn("wait_for_csw(", text)
        self.assertIn("dma_ring_invalidate_result(", text)
        self.assertIn("compare_buffers(", text)
        self.assertIn("RAWCOPY INVALIDATE COMPARE DIAG", text)
        self.assertIn("RAWCOPY_INVALIDATE_COMPARE_STAGE WAIT_DONE", text)
        self.assertIn("RAWCOPY_INVALIDATE_COMPARE_STAGE BEFORE_INVALIDATE", text)
        self.assertIn("RAWCOPY_INVALIDATE_COMPARE_STAGE AFTER_COMPARE match=", text)
        self.assertIn("RAWCOPY_INVALIDATE_COMPARE_OK", text)
        self.assertIn("RAWCOPY_INVALIDATE_COMPARE_HEARTBEAT", text)
        self.assertNotIn("DMA raw-copy smoke PASS", text)

    def test_invalidate_compare_lscript_contract_if_present(self):
        if not DIAG_LSCRIPT.exists():
            self.skipTest(f"Invalidate/compare diag linker script not present yet: {DIAG_LSCRIPT}")

        text = DIAG_LSCRIPT.read_text(encoding="ascii")
        self.assertIn(".dma_desc_region", text)
        self.assertIn(".dma_src_region", text)
        self.assertIn(".dma_dst_region", text)

    def test_boot_release_contract_if_files_exist(self):
        existing = [
            path for path in (DIAG_BUILD_BOOT, DIAG_DEPLOY, DIAG_BOOT_BIF)
            if path.exists()
        ]
        if not existing:
            self.skipTest("Invalidate/compare diag boot/deploy artifacts not present yet")

        for required in (DIAG_BUILD_BOOT, DIAG_DEPLOY, DIAG_BOOT_BIF):
            self.assertTrue(required.exists(), f"Expected staged invalidate/compare diag artifact missing: {required}")

        lines = [
            line.strip()
            for line in DIAG_BOOT_BIF.read_text(encoding="ascii").splitlines()
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
