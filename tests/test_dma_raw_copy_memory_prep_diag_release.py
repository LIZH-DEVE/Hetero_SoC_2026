import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

MEMORY_PREP_MAIN = HCS_SOC / "ax7020_dma_raw_copy_memory_prep_diag_app" / "src" / "main.c"
MEMORY_PREP_LSCRIPT = HCS_SOC / "ax7020_dma_raw_copy_memory_prep_diag_app" / "src" / "lscript.ld"
MEMORY_PREP_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_memory_prep_diag_boot.ps1"
MEMORY_PREP_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_memory_prep_diag_to_sd.ps1"
MEMORY_PREP_BOOT_BIF = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_memory_prep_diag" / "boot.bif"


class TestDmaRawCopyMemoryPrepDiagRelease(unittest.TestCase):
    def test_memory_prep_app_contract_if_present(self):
        if not MEMORY_PREP_MAIN.exists():
            self.skipTest(f"Memory-prep diag app not present yet: {MEMORY_PREP_MAIN}")

        text = MEMORY_PREP_MAIN.read_text(encoding="ascii")
        self.assertIn('dma_hw_regs.h', text)
        self.assertIn('dma_mvp_ps_driver_ref.h', text)
        self.assertIn('.dma_desc_region', text)
        self.assertIn('.dma_src_region', text)
        self.assertIn('.dma_dst_region', text)
        self.assertIn("clear_regions(", text)
        self.assertIn("seed_raw_copy_buffers(", text)
        self.assertNotIn("0x40000000", text)
        self.assertNotIn("dma_ring_init(", text)
        self.assertNotIn("dma_ring_submit(", text)
        self.assertNotIn("dma_ring_submit_raw_copy(", text)
        self.assertNotIn("dma_ring_soft_reset(", text)
        self.assertIn("RAWCOPY MEMORY PREP DIAG", text)
        self.assertIn("RAWCOPY_MEMORY_PREP_OK", text)
        self.assertIn("RAWCOPY_MEMORY_HEARTBEAT", text)

    def test_memory_prep_lscript_contract_if_present(self):
        if not MEMORY_PREP_LSCRIPT.exists():
            self.skipTest(f"Memory-prep diag linker script not present yet: {MEMORY_PREP_LSCRIPT}")

        text = MEMORY_PREP_LSCRIPT.read_text(encoding="ascii")
        self.assertIn(".dma_desc_region", text)
        self.assertIn(".dma_src_region", text)
        self.assertIn(".dma_dst_region", text)

    def test_boot_release_contract_if_files_exist(self):
        existing = [
            path for path in (MEMORY_PREP_BUILD_BOOT, MEMORY_PREP_DEPLOY, MEMORY_PREP_BOOT_BIF)
            if path.exists()
        ]
        if not existing:
            self.skipTest("Memory-prep diag boot/deploy artifacts not present yet")

        for required in (MEMORY_PREP_BUILD_BOOT, MEMORY_PREP_DEPLOY, MEMORY_PREP_BOOT_BIF):
            self.assertTrue(required.exists(), f"Expected staged memory-prep diag artifact missing: {required}")

        lines = [
            line.strip()
            for line in MEMORY_PREP_BOOT_BIF.read_text(encoding="ascii").splitlines()
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
