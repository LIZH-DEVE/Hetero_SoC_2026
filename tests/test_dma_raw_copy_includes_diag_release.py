import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

INCLUDES_DIAG_MAIN = HCS_SOC / "ax7020_dma_raw_copy_includes_diag_app" / "src" / "main.c"
INCLUDES_DIAG_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_includes_diag_boot.ps1"
INCLUDES_DIAG_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_includes_diag_to_sd.ps1"
INCLUDES_DIAG_BOOT_BIF = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_includes_diag" / "boot.bif"


class TestDmaRawCopyIncludesDiagRelease(unittest.TestCase):
    def test_includes_diag_app_contract_if_present(self):
        if not INCLUDES_DIAG_MAIN.exists():
            self.skipTest(f"Includes diag app not present yet: {INCLUDES_DIAG_MAIN}")

        text = INCLUDES_DIAG_MAIN.read_text(encoding="ascii")
        self.assertIn('dma_hw_regs.h', text)
        self.assertIn('dma_mvp_ps_driver_ref.h', text)
        self.assertNotIn("0x40000000", text)
        self.assertNotIn(".dma_desc_region", text)
        self.assertNotIn(".dma_src_region", text)
        self.assertNotIn(".dma_dst_region", text)
        self.assertNotIn("dma_ring_init(", text)
        self.assertNotIn("dma_ring_submit(", text)
        self.assertNotIn("dma_ring_submit_raw_copy(", text)
        self.assertNotIn("dma_ring_soft_reset(", text)
        self.assertIn("RAWCOPY INCLUDES DIAG", text)
        self.assertIn("RAWCOPY_INCLUDE_HEADERS_OK", text)
        self.assertIn("RAWCOPY_INCLUDE_HEARTBEAT", text)

    def test_boot_release_contract_if_files_exist(self):
        existing = [
            path for path in (INCLUDES_DIAG_BUILD_BOOT, INCLUDES_DIAG_DEPLOY, INCLUDES_DIAG_BOOT_BIF)
            if path.exists()
        ]
        if not existing:
            self.skipTest("Includes diag boot/deploy artifacts not present yet")

        for required in (INCLUDES_DIAG_BUILD_BOOT, INCLUDES_DIAG_DEPLOY, INCLUDES_DIAG_BOOT_BIF):
            self.assertTrue(required.exists(), f"Expected staged includes diag artifact missing: {required}")

        lines = [
            line.strip()
            for line in INCLUDES_DIAG_BOOT_BIF.read_text(encoding="ascii").splitlines()
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
