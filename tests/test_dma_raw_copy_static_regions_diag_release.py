import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

STATIC_MAIN = HCS_SOC / "ax7020_dma_raw_copy_static_regions_diag_app" / "src" / "main.c"
STATIC_LSCRIPT = HCS_SOC / "ax7020_dma_raw_copy_static_regions_diag_app" / "src" / "lscript.ld"
STATIC_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_static_regions_diag_boot.ps1"
STATIC_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_static_regions_diag_to_sd.ps1"
STATIC_BOOT_BIF = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_static_regions_diag" / "boot.bif"


class TestDmaRawCopyStaticRegionsDiagRelease(unittest.TestCase):
    def test_static_regions_app_contract_if_present(self):
        if not STATIC_MAIN.exists():
            self.skipTest(f"Static-regions diag app not present yet: {STATIC_MAIN}")

        text = STATIC_MAIN.read_text(encoding="ascii")
        self.assertIn('dma_hw_regs.h', text)
        self.assertIn('dma_mvp_ps_driver_ref.h', text)
        self.assertIn('.dma_desc_region', text)
        self.assertIn('.dma_src_region', text)
        self.assertIn('.dma_dst_region', text)
        self.assertNotIn("0x40000000", text)
        self.assertNotIn("dma_ring_init(", text)
        self.assertNotIn("dma_ring_submit(", text)
        self.assertNotIn("dma_ring_submit_raw_copy(", text)
        self.assertNotIn("dma_ring_soft_reset(", text)
        self.assertIn("RAWCOPY STATIC REGIONS DIAG", text)
        self.assertIn("RAWCOPY_STATIC_REGIONS_OK", text)
        self.assertIn("RAWCOPY_STATIC_HEARTBEAT", text)

    def test_static_regions_lscript_contract_if_present(self):
        if not STATIC_LSCRIPT.exists():
            self.skipTest(f"Static-regions diag linker script not present yet: {STATIC_LSCRIPT}")

        text = STATIC_LSCRIPT.read_text(encoding="ascii")
        self.assertIn(".dma_desc_region", text)
        self.assertIn(".dma_src_region", text)
        self.assertIn(".dma_dst_region", text)

    def test_boot_release_contract_if_files_exist(self):
        existing = [
            path for path in (STATIC_BUILD_BOOT, STATIC_DEPLOY, STATIC_BOOT_BIF)
            if path.exists()
        ]
        if not existing:
            self.skipTest("Static-regions diag boot/deploy artifacts not present yet")

        for required in (STATIC_BUILD_BOOT, STATIC_DEPLOY, STATIC_BOOT_BIF):
            self.assertTrue(required.exists(), f"Expected staged static-regions diag artifact missing: {required}")

        lines = [
            line.strip()
            for line in STATIC_BOOT_BIF.read_text(encoding="ascii").splitlines()
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
