import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

DRIVER_INIT_MAIN = HCS_SOC / "ax7020_dma_raw_copy_driver_init_diag_app" / "src" / "main.c"
DRIVER_INIT_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_driver_init_diag_boot.ps1"
DRIVER_INIT_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_driver_init_diag_to_sd.ps1"
DRIVER_INIT_BOOT_BIF = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_driver_init_diag" / "boot.bif"


class TestDmaRawCopyDriverInitDiagRelease(unittest.TestCase):
    def test_driver_init_diag_app_contract_if_present(self):
        if not DRIVER_INIT_MAIN.exists():
            self.skipTest(f"Driver-init diag app not present yet: {DRIVER_INIT_MAIN}")

        text = DRIVER_INIT_MAIN.read_text(encoding="ascii")
        self.assertIn("dma_hw_regs.h", text)
        self.assertIn("dma_mvp_ps_driver_ref.h", text)
        self.assertIn("dma_ring_init(", text)
        self.assertNotIn("0x40000000", text)
        self.assertNotIn(".dma_desc_region", text)
        self.assertNotIn(".dma_src_region", text)
        self.assertNotIn(".dma_dst_region", text)
        self.assertNotIn("dma_ring_submit(", text)
        self.assertNotIn("dma_ring_submit_raw_copy(", text)
        self.assertNotIn("dma_ring_soft_reset(", text)
        self.assertNotIn("dma_ring_poll_csw(", text)
        self.assertIn("RAWCOPY DRIVER INIT DIAG", text)
        self.assertIn("RAWCOPY_DRIVER_INIT_OK", text)
        self.assertIn("RAWCOPY_DRIVER_HEARTBEAT", text)

    def test_boot_release_contract_if_files_exist(self):
        existing = [
            path for path in (DRIVER_INIT_BUILD_BOOT, DRIVER_INIT_DEPLOY, DRIVER_INIT_BOOT_BIF)
            if path.exists()
        ]
        if not existing:
            self.skipTest("Driver-init diag boot/deploy artifacts not present yet")

        for required in (DRIVER_INIT_BUILD_BOOT, DRIVER_INIT_DEPLOY, DRIVER_INIT_BOOT_BIF):
            self.assertTrue(required.exists(), f"Expected staged driver-init diag artifact missing: {required}")

        lines = [
            line.strip()
            for line in DRIVER_INIT_BOOT_BIF.read_text(encoding="ascii").splitlines()
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
