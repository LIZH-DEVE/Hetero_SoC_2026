import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
RUNNER = REPO_ROOT / "run_ax7020_udp_gateway_shadow_mirror_jtag.ps1"
FORMAL_RUNNER = REPO_ROOT / "shadow_mirror_jtag_run.ps1"
ROOT_RUNNER = REPO_ROOT.parent / "shadow_mirror_jtag_run.ps1"


class ShadowMirrorJtagLauncherTests(unittest.TestCase):
    def test_runner_uses_start_process_and_tolerates_xsct_stderr_diagnostics(self) -> None:
        runner_text = RUNNER.read_text(encoding="utf-8")

        self.assertIn('Start-Process -FilePath $XsctPath', runner_text)
        self.assertIn('-RedirectStandardOutput', runner_text)
        self.assertIn('-RedirectStandardError', runner_text)
        self.assertNotIn('& $XsctPath @xsctArgs 2>&1 | Out-String', runner_text)

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
