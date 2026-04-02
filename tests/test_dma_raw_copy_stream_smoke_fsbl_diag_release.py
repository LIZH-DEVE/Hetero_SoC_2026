import pathlib
import re
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

TRACE_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_stream_smoke_fsbl_trace_boot.ps1"
TRACE_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_stream_smoke_fsbl_trace_to_sd.ps1"
TRACE_RELEASE_DIR = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_stream_smoke_fsbl_trace"
TRACE_BOOT_BIF = TRACE_RELEASE_DIR / "boot.bif"
TRACE_README = TRACE_RELEASE_DIR / "readme.txt"

NOPCFG_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_stream_smoke_fsbl_nopostcfg_boot.ps1"
NOPCFG_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_stream_smoke_fsbl_nopostcfg_to_sd.ps1"
NOPCFG_RELEASE_DIR = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_stream_smoke_fsbl_nopostcfg"
NOPCFG_BOOT_BIF = NOPCFG_RELEASE_DIR / "boot.bif"
NOPCFG_README = NOPCFG_RELEASE_DIR / "readme.txt"

HANDOFFLITE_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_stream_smoke_fsbl_handofflite_boot.ps1"
HANDOFFLITE_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_stream_smoke_fsbl_handofflite_to_sd.ps1"
HANDOFFLITE_RELEASE_DIR = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_stream_smoke_fsbl_handofflite"
HANDOFFLITE_BOOT_BIF = HANDOFFLITE_RELEASE_DIR / "boot.bif"
HANDOFFLITE_README = HANDOFFLITE_RELEASE_DIR / "readme.txt"

HANDOFFDELAY_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_stream_smoke_fsbl_handoffdelay_boot.ps1"
HANDOFFDELAY_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_stream_smoke_fsbl_handoffdelay_to_sd.ps1"
HANDOFFDELAY_RELEASE_DIR = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_stream_smoke_fsbl_handoffdelay"
HANDOFFDELAY_BOOT_BIF = HANDOFFDELAY_RELEASE_DIR / "boot.bif"
HANDOFFDELAY_README = HANDOFFDELAY_RELEASE_DIR / "readme.txt"


def _read_boot_payload(boot_bif: pathlib.Path) -> list[str]:
    lines = [
        line.strip()
        for line in boot_bif.read_text(encoding="ascii").splitlines()
        if line.strip() and not line.strip().startswith("//")
    ]
    return lines[2:-1]


def _find_generated_fsbl_main(tag: str) -> pathlib.Path | None:
    tag = tag.lower()
    for path in HCS_SOC.rglob("main.c"):
        path_text = str(path).lower()
        if "zynq_fsbl" in path.parts and tag in path_text:
            return path
    return None


def _find_generated_fsbl_xparameters(tag: str) -> pathlib.Path | None:
    tag = tag.lower()
    for path in HCS_SOC.rglob("xparameters.h"):
        path_text = str(path).lower()
        if "zynq_fsbl" in path_text and tag in path_text:
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


def _assert_deploy_contract(
    testcase: unittest.TestCase,
    deploy_text: str,
    expected_variant: str,
) -> None:
    if "SHA256 mismatch after deploy" in deploy_text:
        return

    testcase.assertIn("deploy_ax7020_dma_raw_copy_stream_smoke_fsbl_diag_to_sd_common.ps1", deploy_text)
    testcase.assertIn(f"-Variant {expected_variant}", deploy_text)


class TestDmaRawCopyStreamSmokeFsblDiagRelease(unittest.TestCase):
    def test_trace_release_assets_if_present(self):
        existing = [
            path for path in (TRACE_BUILD_BOOT, TRACE_DEPLOY, TRACE_BOOT_BIF, TRACE_README)
            if path.exists()
        ]
        if not existing:
            self.skipTest("FSBL trace diagnostic release artifacts not present yet")

        for required in (TRACE_BUILD_BOOT, TRACE_DEPLOY, TRACE_BOOT_BIF, TRACE_README):
            self.assertTrue(required.exists(), f"Expected FSBL trace artifact missing: {required}")

        build_text = TRACE_BUILD_BOOT.read_text(encoding="ascii")
        deploy_text = TRACE_DEPLOY.read_text(encoding="ascii")
        readme_text = TRACE_README.read_text(encoding="ascii")
        payload = _read_boot_payload(TRACE_BOOT_BIF)

        self.assertIn("stream_smoke_dma_wrapper.bit", build_text)
        self.assertIn("ax7020_dma_raw_copy_stream_smoke_app.elf", build_text)
        self.assertIn("fsbl", build_text.lower())
        self.assertIn("trace", build_text.lower())
        self.assertIn("experimental", readme_text.lower())
        self.assertIn("FSBL_DIAG AFTER_PS7_INIT", readme_text)
        self.assertIn("bootgen -read", build_text)
        _assert_deploy_contract(self, deploy_text, "handofflite")
        self.assertEqual(len(payload), 3)
        self.assertTrue(payload[0].startswith("[bootloader] "))
        self.assertEqual(payload[1], "stream_smoke_dma_wrapper.bit")
        self.assertEqual(payload[2], "ax7020_dma_raw_copy_stream_smoke_app.elf")

    def test_nopostcfg_release_assets_if_present(self):
        existing = [
            path for path in (NOPCFG_BUILD_BOOT, NOPCFG_DEPLOY, NOPCFG_BOOT_BIF, NOPCFG_README)
            if path.exists()
        ]
        if not existing:
            self.skipTest("FSBL no-post-config diagnostic release artifacts not present yet")

        for required in (NOPCFG_BUILD_BOOT, NOPCFG_DEPLOY, NOPCFG_BOOT_BIF, NOPCFG_README):
            self.assertTrue(required.exists(), f"Expected FSBL no-post-config artifact missing: {required}")

        build_text = NOPCFG_BUILD_BOOT.read_text(encoding="ascii")
        deploy_text = NOPCFG_DEPLOY.read_text(encoding="ascii")
        readme_text = NOPCFG_README.read_text(encoding="ascii")
        payload = _read_boot_payload(NOPCFG_BOOT_BIF)

        self.assertIn("stream_smoke_dma_wrapper.bit", build_text)
        self.assertIn("ax7020_dma_raw_copy_stream_smoke_app.elf", build_text)
        self.assertIn("post_config", build_text.lower())
        self.assertIn("no-post-config", readme_text.lower())
        self.assertIn("temporary board-proven Phase 3 baseline", readme_text)
        _assert_deploy_contract(self, deploy_text, "handoffdelay")
        self.assertEqual(len(payload), 3)
        self.assertTrue(payload[0].startswith("[bootloader] "))
        self.assertEqual(payload[1], "stream_smoke_dma_wrapper.bit")
        self.assertEqual(payload[2], "ax7020_dma_raw_copy_stream_smoke_app.elf")

    def test_handofflite_release_assets_if_present(self):
        existing = [
            path for path in (HANDOFFLITE_BUILD_BOOT, HANDOFFLITE_DEPLOY, HANDOFFLITE_BOOT_BIF, HANDOFFLITE_README)
            if path.exists()
        ]
        if not existing:
            self.skipTest("FSBL handofflite diagnostic release artifacts not present yet")

        for required in (HANDOFFLITE_BUILD_BOOT, HANDOFFLITE_DEPLOY, HANDOFFLITE_BOOT_BIF, HANDOFFLITE_README):
            self.assertTrue(required.exists(), f"Expected FSBL handofflite artifact missing: {required}")

        build_text = HANDOFFLITE_BUILD_BOOT.read_text(encoding="ascii")
        deploy_text = HANDOFFLITE_DEPLOY.read_text(encoding="ascii")
        readme_text = HANDOFFLITE_README.read_text(encoding="ascii")
        payload = _read_boot_payload(HANDOFFLITE_BOOT_BIF)

        self.assertIn("stream_smoke_dma_wrapper.bit", build_text)
        self.assertIn("ax7020_dma_raw_copy_stream_smoke_app.elf", build_text)
        self.assertIn("handofflite", build_text.lower())
        self.assertIn("minimal-perturbation", readme_text.lower())
        self.assertIn("FSBL_DIAG BEFORE_POST_CONFIG", readme_text)
        _assert_deploy_contract(self, deploy_text, "handofflite")
        self.assertEqual(len(payload), 3)
        self.assertTrue(payload[0].startswith("[bootloader] "))
        self.assertEqual(payload[1], "stream_smoke_dma_wrapper.bit")
        self.assertEqual(payload[2], "ax7020_dma_raw_copy_stream_smoke_app.elf")

    def test_handoffdelay_release_assets_if_present(self):
        existing = [
            path for path in (HANDOFFDELAY_BUILD_BOOT, HANDOFFDELAY_DEPLOY, HANDOFFDELAY_BOOT_BIF, HANDOFFDELAY_README)
            if path.exists()
        ]
        if not existing:
            self.skipTest("FSBL handoffdelay diagnostic release artifacts not present yet")

        for required in (HANDOFFDELAY_BUILD_BOOT, HANDOFFDELAY_DEPLOY, HANDOFFDELAY_BOOT_BIF, HANDOFFDELAY_README):
            self.assertTrue(required.exists(), f"Expected FSBL handoffdelay artifact missing: {required}")

        build_text = HANDOFFDELAY_BUILD_BOOT.read_text(encoding="ascii")
        deploy_text = HANDOFFDELAY_DEPLOY.read_text(encoding="ascii")
        readme_text = HANDOFFDELAY_README.read_text(encoding="ascii")
        payload = _read_boot_payload(HANDOFFDELAY_BOOT_BIF)

        self.assertIn("stream_smoke_dma_wrapper.bit", build_text)
        self.assertIn("ax7020_dma_raw_copy_stream_smoke_app.elf", build_text)
        self.assertIn("handoffdelay", build_text.lower())
        self.assertIn("no new uart breadcrumbs", readme_text.lower())
        self.assertIn("FsblHookBeforeHandoff()", readme_text)
        _assert_deploy_contract(self, deploy_text, "handoffdelay")
        self.assertEqual(len(payload), 3)
        self.assertTrue(payload[0].startswith("[bootloader] "))
        self.assertEqual(payload[1], "stream_smoke_dma_wrapper.bit")
        self.assertEqual(payload[2], "ax7020_dma_raw_copy_stream_smoke_app.elf")

    def test_generated_trace_fsbl_main_and_bsp_if_present(self):
        main_path = _find_generated_fsbl_main("trace")
        xparams_path = _find_generated_fsbl_xparameters("trace")
        if main_path is None and xparams_path is None:
            self.skipTest("Generated trace FSBL workspace artifacts not present yet")

        self.assertIsNotNone(main_path, "Expected generated trace FSBL main.c")
        self.assertIsNotNone(xparams_path, "Expected generated trace FSBL BSP xparameters.h")

        main_text = main_path.read_text(encoding="ascii")
        xparams_text = xparams_path.read_text(encoding="ascii")

        self.assertIn("FSBL_DIAG AFTER_PS7_INIT", main_text)
        self.assertNotIn("FSBL_DIAG ENTER_MAIN", main_text)
        self.assertIn("xil_printf", main_text)
        self.assertIn("XUARTPS_SR_TXEMPTY", main_text)
        self.assertIn("STDOUT_BASEADDRESS", main_text)
        self.assertIn("XPAR_XUARTPS_0_BASEADDR", xparams_text)
        self.assertIn("STDOUT_BASEADDRESS", xparams_text)

        handoff_block = _extract_function_block(main_text, "void FsblHandoff(u32 FsblStartAddr)")
        jtag_window = _slice_between(
            main_text,
            "if (BootModeRegister == JTAG_MODE)",
            "HandoffAddress = LoadBootImage();",
        )

        self.assertEqual(main_text.count("FSBL_DIAG BEFORE_POST_CONFIG"), 1)
        self.assertEqual(main_text.count("FSBL_DIAG AFTER_POST_CONFIG"), 1)
        self.assertEqual(main_text.count("FSBL_DIAG BEFORE_HANDOFF"), 1)
        self.assertIn("FSBL_DIAG BEFORE_POST_CONFIG", handoff_block)
        self.assertIn("FSBL_DIAG AFTER_POST_CONFIG", handoff_block)
        self.assertIn("FSBL_DIAG BEFORE_HANDOFF", handoff_block)
        self.assertIn("ps7_post_config();", handoff_block)
        self.assertNotIn("FSBL_DIAG BEFORE_POST_CONFIG", jtag_window)
        self.assertNotIn("FSBL_DIAG AFTER_POST_CONFIG", jtag_window)
        self.assertLess(
            handoff_block.index("FSBL_DIAG BEFORE_POST_CONFIG"),
            handoff_block.index("ps7_post_config();"),
        )
        self.assertLess(
            handoff_block.index("ps7_post_config();"),
            handoff_block.index("FSBL_DIAG AFTER_POST_CONFIG"),
        )
        self.assertLess(
            handoff_block.index("FSBL_DIAG BEFORE_HANDOFF"),
            handoff_block.index("Status = FsblHookBeforeHandoff();"),
        )

    def test_generated_nopostcfg_fsbl_main_and_bsp_if_present(self):
        main_path = _find_generated_fsbl_main("nopostcfg")
        xparams_path = _find_generated_fsbl_xparameters("nopostcfg")
        if main_path is None and xparams_path is None:
            self.skipTest("Generated no-post-config FSBL workspace artifacts not present yet")

        self.assertIsNotNone(main_path, "Expected generated no-post-config FSBL main.c")
        self.assertIsNotNone(xparams_path, "Expected generated no-post-config FSBL BSP xparameters.h")

        main_text = main_path.read_text(encoding="ascii")
        xparams_text = xparams_path.read_text(encoding="ascii")

        self.assertIn("FSBL_DIAG AFTER_PS7_INIT", main_text)
        self.assertNotIn("FSBL_DIAG ENTER_MAIN", main_text)
        self.assertIn("xil_printf", main_text)
        self.assertIn("XUARTPS_SR_TXEMPTY", main_text)
        self.assertIn("STDOUT_BASEADDRESS", main_text)
        self.assertIn("XPAR_XUARTPS_0_BASEADDR", xparams_text)
        self.assertIn("STDOUT_BASEADDRESS", xparams_text)

        handoff_block = _extract_function_block(main_text, "void FsblHandoff(u32 FsblStartAddr)")
        jtag_window = _slice_between(
            main_text,
            "if (BootModeRegister == JTAG_MODE)",
            "HandoffAddress = LoadBootImage();",
        )

        self.assertEqual(main_text.count("FSBL_DIAG BEFORE_POST_CONFIG"), 1)
        self.assertEqual(main_text.count("FSBL_DIAG AFTER_POST_CONFIG"), 1)
        self.assertEqual(main_text.count("FSBL_DIAG BEFORE_HANDOFF"), 1)
        self.assertIn("FSBL_DIAG BEFORE_POST_CONFIG", handoff_block)
        self.assertIn("FSBL_DIAG AFTER_POST_CONFIG", handoff_block)
        self.assertIn("FSBL_DIAG BEFORE_HANDOFF", handoff_block)
        self.assertNotIn("ps7_post_config();", handoff_block)
        self.assertIn("ps7_post_config();", jtag_window)
        self.assertLess(
            handoff_block.index("FSBL_DIAG BEFORE_HANDOFF"),
            handoff_block.index("Status = FsblHookBeforeHandoff();"),
        )

    def test_generated_handofflite_fsbl_main_and_bsp_if_present(self):
        main_path = _find_generated_fsbl_main("handofflite")
        xparams_path = _find_generated_fsbl_xparameters("handofflite")
        if main_path is None and xparams_path is None:
            self.skipTest("Generated handofflite FSBL workspace artifacts not present yet")

        self.assertIsNotNone(main_path, "Expected generated handofflite FSBL main.c")
        self.assertIsNotNone(xparams_path, "Expected generated handofflite FSBL BSP xparameters.h")

        main_text = main_path.read_text(encoding="ascii")
        xparams_text = xparams_path.read_text(encoding="ascii")

        self.assertNotIn("FSBL_DIAG ENTER_MAIN", main_text)
        self.assertNotIn("FSBL_DIAG AFTER_PS7_INIT", main_text)
        self.assertNotIn("FSBL_DIAG BEFORE_PCAP_LOAD", main_text)
        self.assertNotIn("FSBL_DIAG AFTER_PCAP_LOAD", main_text)
        self.assertIn("xil_printf", main_text)
        self.assertIn("XUARTPS_SR_TXEMPTY", main_text)
        self.assertIn("STDOUT_BASEADDRESS", main_text)
        self.assertIn("XPAR_XUARTPS_0_BASEADDR", xparams_text)
        self.assertIn("STDOUT_BASEADDRESS", xparams_text)

        handoff_block = _extract_function_block(main_text, "void FsblHandoff(u32 FsblStartAddr)")
        jtag_window = _slice_between(
            main_text,
            "if (BootModeRegister == JTAG_MODE)",
            "HandoffAddress = LoadBootImage();",
        )

        self.assertEqual(main_text.count("FSBL_DIAG BEFORE_POST_CONFIG"), 1)
        self.assertEqual(main_text.count("FSBL_DIAG AFTER_POST_CONFIG"), 1)
        self.assertEqual(main_text.count("FSBL_DIAG BEFORE_HANDOFF"), 1)
        self.assertIn("FSBL_DIAG BEFORE_POST_CONFIG", handoff_block)
        self.assertIn("FSBL_DIAG AFTER_POST_CONFIG", handoff_block)
        self.assertIn("FSBL_DIAG BEFORE_HANDOFF", handoff_block)
        self.assertIn("ps7_post_config();", handoff_block)
        self.assertNotIn("FSBL_DIAG BEFORE_POST_CONFIG", jtag_window)
        self.assertNotIn("FSBL_DIAG AFTER_POST_CONFIG", jtag_window)
        self.assertLess(
            handoff_block.index("FSBL_DIAG BEFORE_POST_CONFIG"),
            handoff_block.index("ps7_post_config();"),
        )
        self.assertLess(
            handoff_block.index("ps7_post_config();"),
            handoff_block.index("FSBL_DIAG AFTER_POST_CONFIG"),
        )
        self.assertLess(
            handoff_block.index("FSBL_DIAG BEFORE_HANDOFF"),
            handoff_block.index("Status = FsblHookBeforeHandoff();"),
        )

    def test_generated_handoffdelay_fsbl_main_and_bsp_if_present(self):
        main_path = _find_generated_fsbl_main("handoffdelay")
        xparams_path = _find_generated_fsbl_xparameters("handoffdelay")
        if main_path is None and xparams_path is None:
            self.skipTest("Generated handoffdelay FSBL workspace artifacts not present yet")

        self.assertIsNotNone(main_path, "Expected generated handoffdelay FSBL main.c")
        self.assertIsNotNone(xparams_path, "Expected generated handoffdelay FSBL BSP xparameters.h")

        main_text = main_path.read_text(encoding="ascii")
        xparams_text = xparams_path.read_text(encoding="ascii")

        self.assertNotIn("FSBL_DIAG ", main_text)
        self.assertIn("FsblDiagDelaySpin", main_text)
        self.assertIn("STDOUT_BASEADDRESS", xparams_text)
        self.assertIn("XPAR_XUARTPS_0_BASEADDR", xparams_text)

        handoff_block = _extract_function_block(main_text, "void FsblHandoff(u32 FsblStartAddr)")
        jtag_window = _slice_between(
            main_text,
            "if (BootModeRegister == JTAG_MODE)",
            "HandoffAddress = LoadBootImage();",
        )

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
