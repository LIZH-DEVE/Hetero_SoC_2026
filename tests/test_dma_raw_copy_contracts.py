import pathlib
import re
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

DRIVER_H = HCS_SOC / "dma_mvp_ps_driver_ref.h"
DRIVER_C = HCS_SOC / "dma_mvp_ps_driver_ref.c"
MAIN_C = HCS_SOC / "ax7020_dma_raw_copy_smoke_app" / "src" / "main.c"
LSCRIPT = HCS_SOC / "ax7020_dma_raw_copy_smoke_app" / "src" / "lscript.ld"
BUILD_APP = HCS_SOC / "build_ax7020_dma_raw_copy_smoke_app.ps1"
BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_smoke_boot.ps1"
DEPLOY_SD = HCS_SOC / "deploy_ax7020_dma_raw_copy_smoke_to_sd.ps1"
BOOT_BIF = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_smoke" / "boot.bif"


class TestDmaRawCopyContracts(unittest.TestCase):
    def test_driver_header_uses_contract_header_without_local_dma_macros(self):
        text = DRIVER_H.read_text(encoding="ascii")
        self.assertIn('#include "dma_hw_regs.h"', text)
        self.assertIn("typedef dma_desc_t dma_ring_desc_t;", text)
        self.assertNotRegex(text, r"#define\s+DMA_CSR_")
        self.assertNotRegex(text, r"#define\s+DMA_DESC_")
        self.assertNotRegex(text, r"#define\s+DMA_CTRL_")

    def test_driver_uses_contract_alignment_and_soft_reset_pulse(self):
        text = DRIVER_C.read_text(encoding="ascii")
        self.assertIn("DMA_RAW_COPY_LEN_MULTIPLE", text)
        self.assertIn("DMA_ALIGNMENT_BYTES", text)
        self.assertIn("DMA_DESC_CTRL_MASK_LEN", text)
        self.assertIn("DMA_DESC_CTRL_BIT_ALGO", text)
        self.assertRegex(
            text,
            r"Xil_Out32\(\(UINTPTR\)\(ctx->csr_base \+ DMA_CSR_CTRL\), DMA_CTRL_SOFT_RESET\);"
            r"[\s\S]*?Xil_Out32\(\(UINTPTR\)\(ctx->csr_base \+ DMA_CSR_CTRL\), 0u\);",
        )

    def test_main_enforces_alignment_regions_and_post_csw_invalidate(self):
        text = MAIN_C.read_text(encoding="ascii")
        self.assertIn('#include "dma_hw_regs.h"', text)
        self.assertIn("RAW_COPY_BYTES (DMA_RAW_COPY_LEN_MULTIPLE * 2u)", text)
        self.assertIn('section(".dma_desc_region")', text)
        self.assertIn('section(".dma_src_region")', text)
        self.assertIn('section(".dma_dst_region")', text)
        self.assertIn("dma_ring_submit_raw_copy", text)
        self.assertRegex(
            text,
            r"rc = wait_for_csw\(g_ring, &csw\);[\s\S]*?dma_ring_invalidate_result\(g_dst_buffer, RAW_COPY_BYTES\);"
            r"[\s\S]*?compare_buffers\(g_src_buffer, g_dst_buffer, RAW_COPY_BYTES\)",
        )
        for marker in (
            "RAWCOPY_STAGE INIT",
            "RAWCOPY_STAGE RESET",
            "RAWCOPY_STAGE SUBMIT",
            "RAWCOPY_STAGE WAIT_CSW",
            "RAWCOPY_STAGE INVALIDATE_DST",
            "RAWCOPY_STAGE COMPARE",
        ):
            self.assertIn(marker, text)

    def test_linker_script_separates_desc_src_dst_regions(self):
        text = LSCRIPT.read_text(encoding="ascii")
        self.assertIn(".dma_desc_region (NOLOAD)", text)
        self.assertIn(".dma_src_region (NOLOAD)", text)
        self.assertIn(".dma_dst_region (NOLOAD)", text)

    def test_build_and_deploy_scripts_are_fail_fast_and_hash_guarded(self):
        app_text = BUILD_APP.read_text(encoding="ascii")
        boot_text = BUILD_BOOT.read_text(encoding="ascii")
        deploy_text = DEPLOY_SD.read_text(encoding="ascii")
        self.assertIn('Join-Path $workspace "dma_hw_regs.h"', app_text)
        self.assertIn("ax7020_dma_raw_copy_platform\\ps7_cortexa9_0\\standalone_domain\\bsp\\ps7_cortexa9_0", app_text)
        self.assertIn("standalone_bsp\\ps7_cortexa9_0", app_text)
        self.assertIn("Resolve-PlatformApiBspRoot", app_text)
        self.assertIn("Resolve-PlatformToolchainRoot", app_text)
        self.assertIn("ax7020_dma_raw_copy_platform\\zynq_fsbl\\zynq_fsbl_bsp\\ps7_cortexa9_0", app_text)
        self.assertIn('Write-Host "API BSP root: $PlatformSwDir"', app_text)
        self.assertIn('Write-Host "Toolchain BSP root: $toolchainRoot"', app_text)
        self.assertIn('$ErrorActionPreference = "Stop"', boot_text)
        self.assertIn("raw_copy_dma_wrapper.xsa", boot_text)
        self.assertIn("export_raw_copy_dma_xsa.ps1", boot_text)
        self.assertIn("generate_ax7020_standalone_platform.ps1", boot_text)
        self.assertIn("fsbl.elf", boot_text)
        self.assertIn("Resolve-RawCopyApiBspRoot", boot_text)
        self.assertIn("ax7020_dma_raw_copy_platform\\ps7_cortexa9_0\\standalone_domain\\bsp\\ps7_cortexa9_0", boot_text)
        self.assertIn("standalone_bsp\\ps7_cortexa9_0", boot_text)
        self.assertIn("same-platform `zynq_fsbl_bsp`", boot_text)
        self.assertIn("bootgen -read", boot_text)
        self.assertIn("bootgen_read.txt", boot_text)
        self.assertNotIn("raw_copy_dma_smoke_xsct", boot_text)
        self.assertIn("Get-FileHash -Algorithm SHA256", boot_text)
        self.assertIn("Get-FileHash -Algorithm SHA256", deploy_text)
        self.assertIn("throw", boot_text)
        self.assertIn("throw", deploy_text)
        self.assertIn("Get-PSDrive -Name", deploy_text)
        self.assertIn("Provider.Name -ne \"FileSystem\"", deploy_text)
        self.assertIn("PathType Leaf", deploy_text)
        self.assertIn("PathType Container", deploy_text)
        self.assertIn("bootgen_read.txt", deploy_text)
        self.assertIn("readme.txt", deploy_text)
        self.assertIn("dma_raw_copy_smoke.bit", deploy_text)
        self.assertIn("ax7020_dma_raw_copy_smoke_app.elf", deploy_text)
        self.assertIn("fsbl.elf", deploy_text)
        self.assertIn("Raw-copy release manifest", deploy_text)

    def test_main_requires_dedicated_raw_copy_csr_macro(self):
        text = MAIN_C.read_text(encoding="ascii")
        self.assertIn("XPAR_DMA_RAW_COPY_SUBSYSTEM_0_BASEADDR", text)
        self.assertIn("XPAR_DMA_RAW_COPY_SUBSYSTEM_0_S_AXIL_BASEADDR", text)
        self.assertNotIn("XPAR_DMA_SUBSYSTEM_V2_WRAPPER_0_BASEADDR", text)

    def test_board_docs_fix_vendor_design1_raw_copy_sequence_and_uart_expectations(self):
        vendor_text = (HCS_SOC / "sd_boot" / "AX7020_VENDOR_BOARD_BASELINES.md").read_text(encoding="ascii")
        repo_text = (HCS_SOC / "sd_boot" / "AX7020_REPO_BOARD_BASELINES.md").read_text(encoding="ascii")

        for text in (vendor_text, repo_text):
            self.assertIn("1. `ax7020_vendor_ps_uart_baseline`", text)
            self.assertIn("2. `ax7020_repo_design1_uart_baseline`", text)
            self.assertIn("3. `ax7020_dma_raw_copy_smoke`", text)

        self.assertIn("4. `ax7020_dma_raw_copy_mvp`", repo_text)
        self.assertNotIn("ax7020_low_lut_raw_copy_dma_smoke", repo_text)
        self.assertIn("Hello ALINX!", vendor_text)
        self.assertIn("REPO DESIGN1 UART BASELINE", repo_text)
        self.assertIn("DMA raw-copy smoke image", repo_text)
        self.assertIn("RAWCOPY_STAGE SUBMIT", repo_text)
        self.assertIn("RAWCOPY_STAGE WAIT_CSW", repo_text)
        self.assertIn("DMA raw-copy smoke PASS", repo_text)
        self.assertIn("Do not skip levels.", repo_text)

    def test_boot_bif_is_clean_three_stage_image(self):
        lines = [
            line.strip()
            for line in BOOT_BIF.read_text(encoding="ascii").splitlines()
            if line.strip() and not line.strip().startswith("//")
        ]
        self.assertEqual(lines[0], "the_ROM_image:")
        self.assertEqual(lines[1], "{")
        self.assertEqual(lines[-1], "}")
        payload = lines[2:-1]
        self.assertEqual(len(payload), 3)
        self.assertTrue(payload[0].startswith("[bootloader] "))
        self.assertEqual(payload[1], "dma_raw_copy_smoke.bit")
        self.assertEqual(payload[2], "ax7020_dma_raw_copy_smoke_app.elf")


if __name__ == "__main__":
    unittest.main()
