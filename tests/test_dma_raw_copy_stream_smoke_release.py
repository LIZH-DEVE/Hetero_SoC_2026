import pathlib
import re
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

STREAM_MAIN = HCS_SOC / "ax7020_dma_raw_copy_stream_smoke_app" / "src" / "main.c"
STREAM_LSCRIPT = HCS_SOC / "ax7020_dma_raw_copy_stream_smoke_app" / "src" / "lscript.ld"
STREAM_BUILD_APP = HCS_SOC / "build_ax7020_dma_raw_copy_stream_smoke_app.ps1"
STREAM_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_stream_smoke_boot.ps1"
STREAM_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_stream_smoke_to_sd.ps1"
STREAM_RELEASE_DIR = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_stream_smoke"
STREAM_BOOT_BIF = STREAM_RELEASE_DIR / "boot.bif"
STREAM_README = STREAM_RELEASE_DIR / "readme.txt"
STREAM_BOOTGEN_READ = STREAM_RELEASE_DIR / "bootgen_read.txt"
FSBL_MATRIX = HCS_SOC / "STREAM_SMOKE_FSBL_MATRIX.md"


def _find_generated_fsbl_main() -> pathlib.Path | None:
    for path in HCS_SOC.rglob("main.c"):
        path_text = str(path).lower()
        if "zynq_fsbl" in path.parts and "ax7020_dma_stream_smoke_platform_xsct" in path_text:
            return path
    return None


def _find_generated_fsbl_xparameters() -> pathlib.Path | None:
    for path in HCS_SOC.rglob("xparameters.h"):
        path_text = str(path).lower()
        if "zynq_fsbl" in path_text and "ax7020_dma_stream_smoke_platform_xsct" in path_text:
            return path
    return None


def _extract_function_block(text: str, signature: str) -> str:
    match = re.search(re.escape(signature), text)
    if match is None:
        raise AssertionError(f"Function signature not found: {signature}")

    open_brace = text.find("{", match.end())
    if open_brace < 0:
        raise AssertionError(f"Opening brace not found for function: {signature}")

    depth = 0
    for index in range(open_brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[match.start(): index + 1]

    raise AssertionError(f"Closing brace not found for function: {signature}")


def _slice_between(text: str, start_marker: str, end_marker: str) -> str:
    start = text.find(start_marker)
    if start < 0:
        raise AssertionError(f"Start marker not found: {start_marker}")

    end = text.find(end_marker, start)
    if end < 0:
        raise AssertionError(f"End marker not found after {start_marker}: {end_marker}")

    return text[start:end]


class TestDmaRawCopyStreamSmokeRelease(unittest.TestCase):
    def test_stream_smoke_assets_exist(self):
        for required in (
            STREAM_MAIN,
            STREAM_LSCRIPT,
            STREAM_BUILD_APP,
            STREAM_BUILD_BOOT,
            STREAM_DEPLOY,
            STREAM_BOOT_BIF,
            STREAM_README,
            STREAM_BOOTGEN_READ,
            FSBL_MATRIX,
        ):
            self.assertTrue(required.exists(), f"Expected stream-smoke asset missing: {required}")

    def test_stream_smoke_app_contract(self):
        text = STREAM_MAIN.read_text(encoding="ascii")

        self.assertIn("dma_hw_regs.h", text)
        self.assertIn("dma_mvp_ps_driver_ref.h", text)
        self.assertIn("stream dummy", text.lower())
        self.assertIn("STREAM_STAGE EXACT_FIT PASS", text)
        self.assertIn("STREAM_STAGE SHORT PASS", text)
        self.assertIn("STREAM_STAGE OVERFLOW PASS", text)
        self.assertIn("DMA stream smoke PASS", text)
        self.assertIn("dma_ring_submit_stream(", text)
        self.assertIn("DMA_DESC_CTRL_STREAM_TLAST", text)
        self.assertIn("DMA_DESC_CSW_STS_OVERFLOW_OR_MISSING_TLAST", text)
        self.assertIn("dma_ring_read_actual_len(", text)
        self.assertIn("PACKET_LEN", text)
        self.assertIn("CTRL", text)
        self.assertIn("STREAM_SMOKE_DMA_BASEADDR 0x40000000u", text)
        self.assertIn("STREAM_DUMMY_BASEADDR 0x40001000u", text)
        self.assertIn("fixed two-window AXI-Lite", text)
        self.assertIn("XPAR_DMA_STREAM_SMOKE_SUBSYSTEM_0_BASEADDR", text)
        self.assertIn("XPAR_DMA_STREAM_SMOKE_SUBSYSTEM_0_S_AXIL_DUMMY_BASEADDR", text)
        self.assertIn("XPAR_STREAM_DUMMY_SOURCE_0_BASEADDR", text)
        self.assertIn("XPAR_STREAM_DUMMY_SOURCE_0_S_AXIL_BASEADDR", text)
        self.assertIn("XPAR_DMA_STREAM_SMOKE_BOARD_WRAPPER_0_BASEADDR", text)
        self.assertNotIn("dma_ring_irq_enable(", text)
        self.assertNotIn("dma_ring_irq_top_half(", text)

    def test_stream_smoke_linker_keeps_dma_regions(self):
        text = STREAM_LSCRIPT.read_text(encoding="ascii")
        self.assertIn(".dma_desc_region", text)
        self.assertIn(".dma_dst_region", text)
        self.assertNotIn(".dma_src_region", text)

    def test_stream_release_contract(self):
        build_text = STREAM_BUILD_BOOT.read_text(encoding="ascii")
        deploy_text = STREAM_DEPLOY.read_text(encoding="ascii")
        readme_text = STREAM_README.read_text(encoding="ascii")
        official_pass_criteria = (
            "DMA stream smoke image",
            "STREAM_STAGE EXACT_FIT PASS actual_len=1024",
            "STREAM_STAGE SHORT PASS actual_len=64",
            "STREAM_STAGE OVERFLOW PASS actual_len=64",
            "DMA stream smoke PASS",
        )

        self.assertIn("stream_smoke_dma_wrapper.xsa", build_text)
        self.assertIn("ax7020_dma_stream_smoke_platform_xsct\\workspace", build_text)
        self.assertIn("ax7020_dma_stream_smoke_platform", build_text)
        self.assertIn("bootgen -read", build_text)
        self.assertIn("stream_smoke_dma_wrapper.bit", build_text)
        self.assertIn("ax7020_dma_raw_copy_stream_smoke_app.elf", build_text)
        self.assertIn("Stream-smoke release manifest", deploy_text)
        self.assertIn("SHA256 mismatch after deploy", deploy_text)
        self.assertIn("experimental dedicated with-bit path", readme_text)
        self.assertIn("not the current board-proven Phase 3 baseline", readme_text)
        self.assertIn("word-granular only", readme_text)
        self.assertIn("temporary board-proven baseline", readme_text)
        self.assertIn("experimental dedicated stream-smoke with-bit image", deploy_text)
        self.assertIn("ax7020_design1fsbl_stream_smoke_app", deploy_text)
        self.assertIn("3 consecutive cold boots", readme_text)
        for expected_line in official_pass_criteria:
            self.assertIn(expected_line, readme_text)
            self.assertIn(expected_line, deploy_text)
        matrix_text = FSBL_MATRIX.read_text(encoding="utf-8")
        self.assertIn("the dedicated FSBL remains the only remaining officialization", matrix_text)

    def test_stream_boot_image_remains_three_stage(self):
        bif_lines = [
            line.strip()
            for line in STREAM_BOOT_BIF.read_text(encoding="ascii").splitlines()
            if line.strip() and not line.strip().startswith("//")
        ]

        self.assertEqual(bif_lines[0], "the_ROM_image:")
        self.assertEqual(bif_lines[1], "{")
        self.assertEqual(bif_lines[-1], "}")
        payload = bif_lines[2:-1]
        self.assertEqual(len(payload), 3)
        self.assertTrue(payload[0].startswith("[bootloader] "))
        self.assertEqual(payload[1], "stream_smoke_dma_wrapper.bit")
        self.assertEqual(payload[2], "ax7020_dma_raw_copy_stream_smoke_app.elf")
        bootgen_text = STREAM_BOOTGEN_READ.read_text(encoding="ascii")
        self.assertIn("fsbl.elf", bootgen_text)
        self.assertIn("stream_smoke_dma_wrapper.bit", bootgen_text)
        self.assertIn("ax7020_dma_raw_copy_stream_smoke_app.elf", bootgen_text)

    def test_generated_official_fsbl_is_delay_only_if_present(self):
        main_path = _find_generated_fsbl_main()
        xparams_path = _find_generated_fsbl_xparameters()
        if main_path is None and xparams_path is None:
            self.skipTest("Generated official stream-smoke FSBL workspace artifacts not present yet")

        self.assertIsNotNone(main_path, "Expected generated official stream-smoke FSBL main.c")
        self.assertIsNotNone(xparams_path, "Expected generated official stream-smoke FSBL BSP xparameters.h")

        main_text = main_path.read_text(encoding="utf-8", errors="ignore")
        xparams_text = xparams_path.read_text(encoding="utf-8", errors="ignore")
        handoff_block = _extract_function_block(main_text, "void FsblHandoff(u32 FsblStartAddr)")
        jtag_window = _slice_between(
            main_text,
            "if (BootModeRegister == JTAG_MODE)",
            "HandoffAddress = LoadBootImage();",
        )

        self.assertNotIn("FSBL_DIAG ", main_text)
        self.assertIn("FsblDiagDelaySpin", main_text)
        self.assertIn("XPAR_XUARTPS_0_BASEADDR", xparams_text)
        self.assertIn("STDOUT_BASEADDRESS", xparams_text)
        self.assertIn("ps7_post_config();", handoff_block)
        self.assertEqual(handoff_block.count("FsblDiagDelaySpin(500000U);"), 2)
        self.assertLess(
            handoff_block.index("ps7_post_config();"),
            handoff_block.index("FsblDiagDelaySpin(500000U);"),
        )
        self.assertLess(
            handoff_block.rindex("FsblDiagDelaySpin(500000U);"),
            handoff_block.index("Status = FsblHookBeforeHandoff();"),
        )
        self.assertIn("ps7_post_config();", jtag_window)


if __name__ == "__main__":
    unittest.main()
