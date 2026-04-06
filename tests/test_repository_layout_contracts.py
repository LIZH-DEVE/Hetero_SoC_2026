import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
DOC_ROOT = REPO_ROOT / "doc"
DOC_ARCHIVE = DOC_ROOT / "archive"
REPO_STRUCTURE = DOC_ROOT / "REPO_STRUCTURE.md"
ROOT_ARCHIVE = REPO_ROOT / "archive"
ROOT_SERIAL_ARCHIVE = ROOT_ARCHIVE / "root_runtime_logs" / "serial"
ROOT_TOOL_ARCHIVE = ROOT_ARCHIVE / "root_tool_logs"
ROOT_DEBUG_ARCHIVE = ROOT_ARCHIVE / "root_debug_scripts"
ROOT_BACKUP_ARCHIVE = ROOT_ARCHIVE / "root_backups"
ROOT_TEMP_ARCHIVE = ROOT_ARCHIVE / "root_temp_workdirs"
ROOT_LOCAL_STATE_ARCHIVE = ROOT_TEMP_ARCHIVE / "local_workspace_state"
LEGACY_ROOT = REPO_ROOT / "legacy"
LEGACY_ROOT_PROJECTS = LEGACY_ROOT / "root_projects"
LEGACY_ROOT_TOOLS = LEGACY_ROOT / "root_tools"
HCS_SOC = REPO_ROOT / "HCS_SOC"
HCS_SOC_ARCHIVE = HCS_SOC / "archive"
HCS_SOC_TRIAGE_ARCHIVE = HCS_SOC_ARCHIVE / "triage"
HCS_SOC_XSA_ARCHIVE = HCS_SOC_ARCHIVE / "xsa_extracts"
HCS_SOC_LEGACY = HCS_SOC / "legacy"
HCS_SOC_LEGACY_APPS = HCS_SOC_LEGACY / "apps"
HCS_SOC_LEGACY_PLATFORMS = HCS_SOC_LEGACY / "platforms"
HCS_SOC_LEGACY_SD_BOOT = HCS_SOC_LEGACY / "sd_boot"
HCS_SOC_LEGACY_ARTIFACTS = HCS_SOC_LEGACY / "artifacts"
HCS_SOC_LEGACY_SCRIPTS = HCS_SOC_LEGACY / "scripts"
HCS_SOC_LEGACY_WORKSPACES = HCS_SOC_LEGACY / "workspaces"
CAPTURE_UART = HCS_SOC / "capture_uart_boot_log.ps1"
DELIVERY_LAYOUT = DOC_ROOT / "DELIVERY_LAYOUT.md"


class TestRepositoryLayoutContracts(unittest.TestCase):
    def test_repo_structure_doc_defines_primary_roots(self):
        text = REPO_STRUCTURE.read_text(encoding="utf-8")

        for token in (
            "# Repository Structure",
            "`doc/` is the primary human-facing documentation root",
            "`docs/` is reserved for tooling or workflow-specific documentation",
            "`archive/root_runtime_logs/serial/`",
            "`archive/root_temp_workdirs/`",
            "`archive/root_temp_workdirs/local_workspace_state/`",
            "`legacy/root_projects/`",
            "`legacy/root_tools/`",
            "`HCS_SOC/archive/triage/`",
            "`HCS_SOC/archive/xsa_extracts/`",
            "`HCS_SOC/legacy/apps/`",
            "`HCS_SOC/legacy/platforms/`",
            "`HCS_SOC/legacy/sd_boot/`",
            "`rtl/`",
            "`constraints/`",
            "`scripts/`",
            "`tests/`",
            "`HCS_SOC/ax7020_udp_gateway_shadow_mirror_app/`",
        ):
            self.assertIn(token, text)

    def test_root_runtime_logs_and_temp_scripts_are_archived(self):
        forbidden_patterns = (
            "board_uart*.txt",
            "board_ax7020*.txt",
            "board_gem0*.txt",
            "board_network_inject*.txt",
            ".codex_tmp*",
            "_codex_uart_probe_after_latest_jtag.txt",
            "*.wdb",
            "*.vcd",
        )

        offenders = []
        for pattern in forbidden_patterns:
            offenders.extend(path.name for path in REPO_ROOT.glob(pattern))

        self.assertEqual([], sorted(offenders))

    def test_root_notes_are_moved_under_doc_archive(self):
        self.assertFalse((REPO_ROOT / "TEST_REPORT.md").exists())
        self.assertFalse((REPO_ROOT / "PROGRESS_SAVE_UART_SUCCESS.md").exists())
        self.assertTrue((DOC_ARCHIVE / "root_notes" / "TEST_REPORT.md").exists())
        self.assertTrue((DOC_ARCHIVE / "root_notes" / "PROGRESS_SAVE_UART_SUCCESS.md").exists())

    def test_hcs_soc_floorplan_scratch_and_extracts_are_archived(self):
        forbidden_patterns = (
            "_codex_*",
            "analysis_utilization_*",
            "shadow_export_debug*",
            "temp_xsa*",
        )

        offenders = []
        for pattern in forbidden_patterns:
            offenders.extend(path.name for path in HCS_SOC.glob(pattern))

        self.assertEqual([], sorted(offenders))
        self.assertTrue(HCS_SOC_TRIAGE_ARCHIVE.exists())
        self.assertTrue(HCS_SOC_XSA_ARCHIVE.exists())

    def test_root_and_hcs_soc_archive_roots_exist(self):
        for required in (
            ROOT_SERIAL_ARCHIVE,
            ROOT_TOOL_ARCHIVE,
            ROOT_DEBUG_ARCHIVE,
            ROOT_BACKUP_ARCHIVE,
            ROOT_TEMP_ARCHIVE,
            ROOT_LOCAL_STATE_ARCHIVE,
            LEGACY_ROOT,
            LEGACY_ROOT_PROJECTS,
            LEGACY_ROOT_TOOLS,
            HCS_SOC_ARCHIVE,
            HCS_SOC_TRIAGE_ARCHIVE,
            HCS_SOC_XSA_ARCHIVE,
            HCS_SOC_LEGACY,
            HCS_SOC_LEGACY_APPS,
            HCS_SOC_LEGACY_PLATFORMS,
            HCS_SOC_LEGACY_SD_BOOT,
            HCS_SOC_LEGACY_ARTIFACTS,
            HCS_SOC_LEGACY_SCRIPTS,
            HCS_SOC_LEGACY_WORKSPACES,
            DOC_ARCHIVE / "root_notes",
            DOC_ARCHIVE / "hcs_soc_notes",
        ):
            self.assertTrue(required.exists(), f"Expected archive directory missing: {required}")

    def test_capture_uart_defaults_logs_under_doc_reports_board_uart(self):
        text = CAPTURE_UART.read_text(encoding="ascii")

        self.assertIn('Join-Path $repoRoot "doc\\reports\\board_uart"', text)
        self.assertIn('New-Item -ItemType Directory -Force -Path $outputDir', text)
        self.assertNotIn('Join-Path $repoRoot ("board_uart_boot_{0}_{1}.txt"', text)

    def test_delivery_layout_doc_exists_and_points_to_active_release_path(self):
        text = DELIVERY_LAYOUT.read_text(encoding="utf-8")

        for token in (
            "# Delivery Layout",
            "`HCS_SOC/HCS_SOC.xpr`",
            "`HCS_SOC/ax7020_udp_gateway_shadow_mirror_app/`",
            "`HCS_SOC/ax7020_udp_gateway_shadow_mirror_platform_xsct/`",
            "`HCS_SOC/sd_boot/ax7020_udp_gateway_shadow_mirror/`",
            "`archive/root_temp_workdirs/local_workspace_state/`",
            "`HCS_SOC/legacy/scripts/`",
            "`HCS_SOC/legacy/workspaces/`",
        ):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
