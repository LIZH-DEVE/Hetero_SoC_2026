import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
RUNNER = REPO_ROOT / "run_ax7020_udp_gateway_shadow_mirror_jtag.ps1"
FORMAL_RUNNER = REPO_ROOT / "shadow_mirror_jtag_run.ps1"
ROOT_RUNNER = REPO_ROOT.parent / "shadow_mirror_jtag_run.ps1"
TCL_RUNNER = REPO_ROOT / "download_ax7020_udp_gateway_shadow_mirror_jtag.tcl"


class ShadowMirrorJtagLauncherTests(unittest.TestCase):
    def test_tcl_runner_retries_target_discovery_and_emits_clear_no_target_diagnostic(self) -> None:
        tcl_text = TCL_RUNNER.read_text(encoding="utf-8")

        self.assertIn("proc ensure_jtag_targets_visible {}", tcl_text)
        self.assertIn('puts "JTAG target discovery retry...', tcl_text)
        self.assertIn('puts "JTAG_TARGET_DUMP_BEGIN"', tcl_text)
        self.assertIn('puts "<none>"', tcl_text)
        self.assertIn(
            'error "no JTAG targets visible to XSCT after retry; check board power, JTAG USB connection, and cable drivers"',
            tcl_text,
        )
        self.assertIn("ensure_jtag_targets_visible", tcl_text)

    def test_tcl_runner_configures_uart1_console_for_115200(self) -> None:
        tcl_text = TCL_RUNNER.read_text(encoding="utf-8")

        self.assertIn("proc configure_uart1_console {}", tcl_text)
        self.assertIn('mwr [expr {$uart1_base + 0x18}] 62', tcl_text)
        self.assertIn('mwr [expr {$uart1_base + 0x34}] 0x0000000D', tcl_text)
        self.assertNotIn('mwr [expr {$uart1_base + 0x34}] 0x00000006', tcl_text)

    def test_runner_uses_start_process_and_tolerates_xsct_stderr_diagnostics(self) -> None:
        runner_text = RUNNER.read_text(encoding="utf-8")

        self.assertIn('Start-Process -FilePath $XsctPath', runner_text)
        self.assertIn('-RedirectStandardOutput', runner_text)
        self.assertIn('-RedirectStandardError', runner_text)
        self.assertNotIn('& $XsctPath @xsctArgs 2>&1 | Out-String', runner_text)
        self.assertIn('if ($output -match "no JTAG targets visible to XSCT after retry")', runner_text)

    def test_runner_prefers_newest_impl_bitstream_over_stale_sd_boot_copy(self) -> None:
        runner_text = RUNNER.read_text(encoding="utf-8")

        self.assertIn("HCS_SOC.runs\\impl_1\\udp_gateway_shadow_mirror_wrapper.bit", runner_text)
        self.assertIn("sd_boot\\ax7020_udp_gateway_shadow_mirror\\udp_gateway_shadow_mirror_wrapper.bit", runner_text)
        self.assertIn("Sort-Object -Property LastWriteTime -Descending", runner_text)

    def test_validate_only_reports_shadow_mirror_artifacts(self) -> None:
        self.assertTrue(RUNNER.exists(), f"Missing JTAG runner: {RUNNER}")

        proc = subprocess.run(
            [
                "powershell.exe",
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(RUNNER),
                "-ValidateOnly",
            ],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        output = proc.stdout + proc.stderr

        self.assertEqual(proc.returncode, 0, output)
        self.assertIn("MODE=validate_only", output)
        self.assertIn("JTAG_VALIDATE_OK", output)
        self.assertIn("udp_gateway_shadow_mirror_wrapper.bit", output)
        self.assertIn("ax7020_udp_gateway_shadow_mirror_app.elf", output)

    def test_formal_runner_supports_skip_bitstream_validate_only(self) -> None:
        self.assertTrue(
            FORMAL_RUNNER.exists(),
            f"Missing formal JTAG runner: {FORMAL_RUNNER}",
        )

        proc = subprocess.run(
            [
                "powershell.exe",
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(FORMAL_RUNNER),
                "-ValidateOnly",
                "-SkipBitstream",
            ],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        output = proc.stdout + proc.stderr

        self.assertEqual(proc.returncode, 0, output)
        self.assertIn("MODE=validate_only", output)
        self.assertIn("SKIP_BITSTREAM=1", output)
        self.assertIn("JTAG_VALIDATE_OK", output)

    def test_repo_root_runner_delegates_to_hcs_soc_runner(self) -> None:
        self.assertTrue(
            ROOT_RUNNER.exists(),
            f"Missing repo-root JTAG runner: {ROOT_RUNNER}",
        )

        proc = subprocess.run(
            [
                "powershell.exe",
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(ROOT_RUNNER),
                "-ValidateOnly",
                "-SkipBitstream",
            ],
            cwd=ROOT_RUNNER.parent,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        output = proc.stdout + proc.stderr

        self.assertEqual(proc.returncode, 0, output)
        self.assertIn("MODE=validate_only", output)
        self.assertIn("SKIP_BITSTREAM=1", output)
        self.assertIn("JTAG_VALIDATE_OK", output)


if __name__ == "__main__":
    unittest.main()
