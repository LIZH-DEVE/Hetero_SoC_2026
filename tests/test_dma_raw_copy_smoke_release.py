import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

RAW_COPY_EXPORT_TCL = HCS_SOC / "export_raw_copy_dma_xsa.tcl"
SMOKE_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_smoke_boot.ps1"
SMOKE_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_smoke_to_sd.ps1"
SMOKE_README = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_smoke" / "readme.txt"
SMOKE_BOOT_BIF = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_smoke" / "boot.bif"
SMOKE_BOOTGEN_READ = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_smoke" / "bootgen_read.txt"
REPO_BOARD_DOC = HCS_SOC / "sd_boot" / "AX7020_REPO_BOARD_BASELINES.md"

PASSING_BASELINE_HASH = "44B63D346F2AEB95973DB13476E7D8B00738E64D1C94D4040A62FA0AC86BD23B"


class TestDmaRawCopySmokeRelease(unittest.TestCase):
    def test_release_scripts_and_readme_freeze_current_baseline(self):
        export_tcl = RAW_COPY_EXPORT_TCL.read_text(encoding="ascii")
        build_text = SMOKE_BUILD_BOOT.read_text(encoding="ascii")
        deploy_text = SMOKE_DEPLOY.read_text(encoding="ascii")
        readme_text = SMOKE_README.read_text(encoding="ascii")

        self.assertIn("raw_copy_dma_dma_raw_copy_subsystem_0_0", export_tcl)
        self.assertIn("set module_ref_synth_wrapper", export_tcl)
        self.assertIn("add_files -norecurse $module_ref_synth_wrapper", export_tcl)
        self.assertIn("bootgen -read", build_text)
        self.assertIn("raw_copy_dma_wrapper.xsa", build_text)
        self.assertIn("Raw-copy release manifest", deploy_text)
        self.assertIn("$ErrorActionPreference = \"Stop\"", deploy_text)
        self.assertIn("Set-StrictMode -Version Latest", deploy_text)
        self.assertIn("SHA256 mismatch after deploy", deploy_text)
        self.assertIn("DMA raw-copy smoke image", readme_text)
        self.assertIn("RAWCOPY_STAGE INIT", readme_text)
        self.assertIn("RAWCOPY_STAGE RESET", readme_text)
        self.assertIn("RAWCOPY_STAGE SUBMIT", readme_text)
        self.assertIn("RAWCOPY_STAGE WAIT_CSW", readme_text)
        self.assertIn("CSW=0x40000000 owner=0 done=1 err=0 sts=0", readme_text)
        self.assertIn("RAWCOPY_STAGE INVALIDATE_DST", readme_text)
        self.assertIn("RAWCOPY_STAGE COMPARE", readme_text)
        self.assertIn("DMA raw-copy smoke PASS", readme_text)
        self.assertIn(PASSING_BASELINE_HASH, readme_text)
        self.assertIn("8 completions or 5000 cycles", readme_text)

    def test_bootgen_readback_and_bif_remain_clean_three_stage_release(self):
        bootgen_text = SMOKE_BOOTGEN_READ.read_text(encoding="ascii")
        bif_lines = [
            line.strip()
            for line in SMOKE_BOOT_BIF.read_text(encoding="ascii").splitlines()
            if line.strip() and not line.strip().startswith("//")
        ]

        self.assertIn("fsbl.elf", bootgen_text)
        self.assertIn("dma_raw_copy_smoke.bit", bootgen_text)
        self.assertIn("ax7020_dma_raw_copy_smoke_app.elf", bootgen_text)
        self.assertEqual(bif_lines[0], "the_ROM_image:")
        self.assertEqual(bif_lines[1], "{")
        self.assertEqual(bif_lines[-1], "}")
        payload = bif_lines[2:-1]
        self.assertEqual(len(payload), 3)
        self.assertTrue(payload[0].startswith("[bootloader] "))
        self.assertEqual(payload[1], "dma_raw_copy_smoke.bit")
        self.assertEqual(payload[2], "ax7020_dma_raw_copy_smoke_app.elf")

    def test_board_doc_freezes_hp0_root_cause_and_sequence(self):
        text = REPO_BOARD_DOC.read_text(encoding="ascii")

        self.assertIn("1. `ax7020_vendor_ps_uart_baseline`", text)
        self.assertIn("2. `ax7020_repo_design1_uart_baseline`", text)
        self.assertIn("3. `ax7020_dma_raw_copy_smoke`", text)
        self.assertIn("S_AXI_HP0", text)
        self.assertIn("WAIT_CSW", text)
        self.assertIn("44B63D346F2AEB95973DB13476E7D8B00738E64D1C94D4040A62FA0AC86BD23B", text)
        self.assertIn("keep one slot open", text)
        self.assertIn("5000 cycles (100us @ 50MHz)", text)
        self.assertIn("ax7020_dma_raw_copy_*_diag", text)


if __name__ == "__main__":
    unittest.main()
