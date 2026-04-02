import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

APP_MAIN = HCS_SOC / "ax7020_dma_gateway_hybrid_smoke_app" / "src" / "main.c"
BUILD_APP_PS1 = HCS_SOC / "build_ax7020_dma_gateway_hybrid_smoke_app.ps1"
BUILD_BOOT_PS1 = HCS_SOC / "build_ax7020_dma_gateway_hybrid_smoke_boot.ps1"
DEPLOY_PS1 = HCS_SOC / "deploy_ax7020_dma_gateway_hybrid_smoke_to_sd.ps1"
EXPORT_XSA_PS1 = HCS_SOC / "export_dma_gateway_hybrid_xsa.ps1"
README_TXT = HCS_SOC / "sd_boot" / "ax7020_dma_gateway_hybrid_smoke" / "readme.txt"


class TestDmaGatewayHybridRelease(unittest.TestCase):
    def test_hybrid_smoke_app_enforces_unaligned_reject_before_injection(self):
        text = APP_MAIN.read_text(encoding="ascii")

        for token in (
            "#define HYBRID_CTRL_BASEADDR 0x40000000u",
            "#define HYBRID_DMA_BASEADDR 0x40001000u",
            "#define WRAP_REG_DROP_WRONG_PORT_COUNT 0xCCu",
            "#define WRAP_REG_DROP_UNALIGNED_COUNT 0xD0u",
            "WRONG_PORT PASS",
            "UNALIGNED_REJECT PASS",
            "return -6;",
        ):
            self.assertIn(token, text)

        reject_idx = text.index("return -6;")
        inj_idx = text.index("wrap_write32(WRAP_REG_INJ_DATA, frame_words[word_idx]);")
        doorbell_idx = text.index("dma_ring_submit_stream(")
        self.assertLess(reject_idx, inj_idx)
        self.assertLess(reject_idx, doorbell_idx)

    def test_release_chain_exists_and_readme_contains_uart_pass_criteria(self):
        build_app = BUILD_APP_PS1.read_text(encoding="ascii")
        build_boot = BUILD_BOOT_PS1.read_text(encoding="ascii")
        deploy = DEPLOY_PS1.read_text(encoding="ascii")
        readme = README_TXT.read_text(encoding="ascii")

        for token in (
            "build_ax7020_dma_gateway_hybrid_smoke_app.ps1",
            "dma_gateway_hybrid_wrapper.xsa",
            "ax7020_dma_gateway_hybrid_smoke_app.elf",
            "ax7020_dma_gateway_hybrid_smoke",
        ):
            self.assertIn(token, build_boot)

        self.assertIn("ax7020_dma_gateway_hybrid_smoke_app", build_app)
        self.assertIn("ax7020_dma_gateway_hybrid_smoke\\BOOT.BIN", deploy)

        for token in (
            "DMA gateway hybrid smoke image",
            "board-proven Phase A hybrid gateway smoke image",
            "C85DDC649E523FB03863CB2B9C842E434E173EE546BDB1FCADC56EB467507AD3",
            "EXACT_FIT PASS",
            "SHORT PASS",
            "OVERFLOW PASS",
            "WRONG_PORT PASS",
            "UNALIGNED_REJECT PASS",
            "DMA gateway hybrid smoke PASS",
        ):
            self.assertIn(token, readme)

    def test_export_script_allows_dry_run_without_requiring_xsa(self):
        export = EXPORT_XSA_PS1.read_text(encoding="ascii")

        for token in (
            "DMA_GATEWAY_HYBRID_EXPORT_DRY_RUN",
            'Write-Host "Hybrid export dry-run completed without generating an XSA."',
        ):
            self.assertIn(token, export)

        dry_run_guard = (
            'if (($env:DMA_GATEWAY_HYBRID_EXPORT_DRY_RUN -eq "1") -and (-not (Test-Path $XsaPath))) {'
        )
        self.assertIn(dry_run_guard, export)
        self.assertLess(
            export.index(dry_run_guard),
            export.index('if (-not (Test-Path $XsaPath)) {'),
        )


if __name__ == "__main__":
    unittest.main()
