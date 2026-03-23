import json
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))


class BitstreamManagerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.temp_dir.name)
        self.authoritative = (
            self.workspace
            / "HCS_SOC.runs"
            / "impl_1"
            / "design_1_wrapper.bit"
        )
        self.authoritative.parent.mkdir(parents=True, exist_ok=True)
        self.authoritative.write_bytes(b"authoritative-bitstream")

        launch_dir = (
            self.workspace
            / "crypto_test_app"
            / "_ide"
            / ".theia"
        )
        launch_dir.mkdir(parents=True, exist_ok=True)
        self.launch_json = launch_dir / "launch.json"

        self.download_tcl = self.workspace / "download_bitstream.tcl"

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _write_launch_json(self, bitstream_file: str) -> None:
        payload = {
            "version": "0.2.0",
            "configurations": [
                {
                    "targetSetup": {
                        "bitstreamFile": bitstream_file,
                    }
                }
            ],
        }
        self.launch_json.write_text(
            json.dumps(payload, indent=2),
            encoding="utf-8",
        )

    def _write_download_tcl(self, bitstream_file: str) -> None:
        self.download_tcl.write_text(
            "\n".join(
                [
                    "connect",
                    f"fpga -f {bitstream_file}",
                    "con",
                ]
            ),
            encoding="utf-8",
        )

    def test_verify_reports_active_source_mismatch(self) -> None:
        self._write_launch_json(
            r"${workspaceFolder}\platform\export\platform\hw\design_1_wrapper.bit"
        )
        self._write_download_tcl(
            "D:/example/platform/export/platform/hw/design_1_wrapper.bit"
        )

        import bitstream_manager

        report = bitstream_manager.verify_workspace(self.workspace)

        self.assertFalse(report.ok)
        self.assertTrue(
            any("launch.json" in issue.message for issue in report.errors)
        )
        self.assertTrue(
            any("download_bitstream.tcl" in issue.message for issue in report.errors)
        )

    def test_verify_accepts_impl1_as_authoritative_source(self) -> None:
        self._write_launch_json(
            r"${workspaceFolder}\HCS_SOC.runs\impl_1\design_1_wrapper.bit"
        )
        self._write_download_tcl(self.authoritative.as_posix())

        import bitstream_manager

        report = bitstream_manager.verify_workspace(self.workspace)

        self.assertTrue(report.ok)
        self.assertEqual([], report.errors)

    def test_publish_creates_latest_and_archive_copy(self) -> None:
        self._write_launch_json(
            r"${workspaceFolder}\HCS_SOC.runs\impl_1\design_1_wrapper.bit"
        )
        self._write_download_tcl(self.authoritative.as_posix())

        import bitstream_manager

        publish_result = bitstream_manager.publish_bitstream(self.workspace)

        self.assertTrue(publish_result.latest_bit.exists())
        self.assertTrue(publish_result.archive_bit.exists())
        self.assertEqual(
            self.authoritative.read_bytes(),
            publish_result.latest_bit.read_bytes(),
        )
        self.assertEqual(
            self.authoritative.read_bytes(),
            publish_result.archive_bit.read_bytes(),
        )

    def test_verify_resolves_tcl_bitstream_variable(self) -> None:
        self._write_launch_json(
            r"${workspaceFolder}\HCS_SOC.runs\impl_1\design_1_wrapper.bit"
        )
        self.download_tcl.write_text(
            "\n".join(
                [
                    f'set bitstream_file "{self.authoritative.as_posix()}"',
                    "fpga -f $bitstream_file",
                ]
            ),
            encoding="utf-8",
        )

        import bitstream_manager

        report = bitstream_manager.verify_workspace(self.workspace)

        self.assertTrue(report.ok)
        self.assertEqual([], report.errors)


if __name__ == "__main__":
    unittest.main()
