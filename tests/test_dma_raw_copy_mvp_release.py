import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

MVP_MAIN = HCS_SOC / "ax7020_dma_raw_copy_mvp_app" / "src" / "main.c"
MVP_LSCRIPT = HCS_SOC / "ax7020_dma_raw_copy_mvp_app" / "src" / "lscript.ld"
MVP_BUILD_APP = HCS_SOC / "build_ax7020_dma_raw_copy_mvp_app.ps1"
MVP_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_mvp_boot.ps1"
MVP_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_mvp_to_sd.ps1"
MVP_RELEASE_DIR = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_mvp"
MVP_BOOT_BIF = MVP_RELEASE_DIR / "boot.bif"
MVP_README = MVP_RELEASE_DIR / "readme.txt"


class TestDmaRawCopyMvpRelease(unittest.TestCase):
    def test_mvp_assets_exist(self):
        for required in (
            MVP_MAIN,
            MVP_LSCRIPT,
            MVP_BUILD_APP,
            MVP_BUILD_BOOT,
            MVP_DEPLOY,
            MVP_BOOT_BIF,
            MVP_README,
        ):
            self.assertTrue(required.exists(), f"Expected MVP asset missing: {required}")

    def test_mvp_app_contract(self):
        text = MVP_MAIN.read_text(encoding="ascii")

        self.assertIn("dma_hw_regs.h", text)
        self.assertIn("dma_mvp_ps_driver_ref.h", text)
        self.assertIn("MVP_RING_ENTRY_COUNT 4u", text)
        self.assertIn("dma_ring_submit_raw_copy(", text)
        self.assertIn("dma_ring_submit_raw_copy_nodoorbell(", text)
        self.assertIn("dma_ring_ring_doorbell(", text)
        self.assertIn("dma_ring_irq_set_coalescing(", text)
        self.assertIn("dma_ring_irq_enable(", text)
        self.assertIn("dma_ring_irq_top_half(", text)
        self.assertIn("dma_ring_read_actual_len(", text)
        self.assertIn("dma_ring_get_hw_head(", text)
        self.assertIn("dma_ring_get_free_slots(", text)
        self.assertIn("MVP_STAGE RING_FILL_QUIESCED", text)
        self.assertIn("MVP_STAGE RING_FULL_CHECK", text)
        self.assertIn("MVP_STAGE RING_FULL_EXPECT submit rc[3]=-5", text)
        self.assertIn("MVP_STAGE RING_RELEASE", text)
        self.assertIn("MVP_IRQ_CONFIG count=2 timeout=64", text)
        self.assertIn("DMA raw-copy MVP PASS", text)

    def test_mvp_linker_script_keeps_dma_regions(self):
        text = MVP_LSCRIPT.read_text(encoding="ascii")
        self.assertIn(".dma_desc_region", text)
        self.assertIn(".dma_src_region", text)
        self.assertIn(".dma_dst_region", text)

    def test_mvp_release_contract(self):
        build_text = MVP_BUILD_BOOT.read_text(encoding="ascii")
        deploy_text = MVP_DEPLOY.read_text(encoding="ascii")
        readme_text = MVP_README.read_text(encoding="ascii")
        bif_lines = [
            line.strip()
            for line in MVP_BOOT_BIF.read_text(encoding="ascii").splitlines()
            if line.strip() and not line.strip().startswith("//")
        ]

        self.assertIn("bootgen -read", build_text)
        self.assertIn("ax7020_dma_raw_copy_mvp_app.elf", build_text)
        self.assertIn("& $exportScript -VivadoBat $VivadoBat -XsaPath $XsaPath", build_text)
        self.assertIn("& $platformScript -XsctBat $XsctBat -XsaPath $XsaPath -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName", build_text)
        self.assertNotIn("Reusing existing dedicated raw-copy XSA/platform workspace:", build_text)
        self.assertNotIn("$needFreshPlatform", build_text)
        self.assertIn("Raw-copy MVP release manifest", deploy_text)
        self.assertIn("SHA256 mismatch after deploy", deploy_text)
        self.assertIn("DMA raw-copy MVP image", readme_text)
        self.assertIn("3 descriptors staged while hardware is quiesced", readme_text)
        self.assertIn("4th staged submit returns -5 before the doorbell is rung", readme_text)
        self.assertIn("Explicit ring/doorbell release then starts hardware consumption", readme_text)
        self.assertIn("count=2", readme_text)
        self.assertIn("timeout=64 cycles", readme_text)
        self.assertIn("DMA raw-copy MVP PASS", readme_text)

        self.assertEqual(bif_lines[0], "the_ROM_image:")
        self.assertEqual(bif_lines[1], "{")
        self.assertEqual(bif_lines[-1], "}")
        payload = bif_lines[2:-1]
        self.assertEqual(len(payload), 3)
        self.assertTrue(payload[0].startswith("[bootloader] "))
        self.assertEqual(payload[1], "dma_raw_copy_mvp.bit")
        self.assertEqual(payload[2], "ax7020_dma_raw_copy_mvp_app.elf")


if __name__ == "__main__":
    unittest.main()
