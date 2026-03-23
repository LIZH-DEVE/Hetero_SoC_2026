import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

import run_udp_crypto_acceptance as acceptance


class AcceptanceScriptTests(unittest.TestCase):
    def test_run_case_returns_subprocess_code(self) -> None:
        with mock.patch("run_udp_crypto_acceptance.subprocess.run") as run_mock:
            run_mock.return_value.returncode = 7
            run_mock.return_value.stdout = "stdout line\n"
            run_mock.return_value.stderr = "stderr line\n"

            output_lines = []
            rc, combined = acceptance.run_case(
                "PING",
                ["ping", "192.168.1.20", "-n", "4"],
                emit=output_lines.append,
            )

        self.assertEqual(rc, 7)
        self.assertIn("stdout line", combined)
        self.assertIn("stderr line", combined)
        self.assertTrue(any("exit_code=7" in line for line in output_lines))
        run_mock.assert_called_once_with(["ping", "192.168.1.20", "-n", "4"], check=False, capture_output=True, text=True)

    def test_script_paths_resolve_under_hcs_soc(self) -> None:
        root = Path(acceptance.__file__).resolve().parent

        self.assertTrue((root / "udp_crypto_control.py").exists())
        self.assertTrue((root / "send_udp_crypto_test.py").exists())
        self.assertTrue((root / "run_udp_crypto_length_regression.py").exists())
        self.assertTrue((root / "run_udp_crypto_control_regression.py").exists())

    def test_execute_acceptance_stops_after_first_failure(self) -> None:
        calls = []

        def fake_runner(cmd, check=False, capture_output=True, text=True):
            del check, capture_output, text
            calls.append(cmd)
            if len(calls) == 1:
                return mock.Mock(returncode=1, stdout="ping failed\n", stderr="")
            return mock.Mock(returncode=0, stdout="unexpected\n", stderr="")

        with TemporaryDirectory() as temp_dir:
            report_dir = Path(temp_dir)
            rc, transcript, report_paths = acceptance.execute_acceptance(
                ip="192.168.1.20",
                source_ip="192.168.1.11",
                timeout=3.0,
                bench_timeout=10.0,
                length_timeout=6.0,
                retries=3,
                retry_delay=0.5,
                send_interval_ms=1.0,
                bench_repeats=8,
                hex_preview_chars=48,
                skip_ping=False,
                host_python="py",
                report_dir=report_dir,
                runner=fake_runner,
                emit=lambda _line: None,
            )

            self.assertTrue(report_paths["raw_log"].exists())
            self.assertTrue(report_paths["report_md"].exists())

        self.assertEqual(rc, 1)
        self.assertEqual(len(calls), 1)
        self.assertIn("ACCEPTANCE_FAILED stage=PING", transcript)


if __name__ == "__main__":
    unittest.main()
