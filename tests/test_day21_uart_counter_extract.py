import importlib.util
import json
import shutil
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPO_ROOT / "scripts" / "day21_uart_counter_extract.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("day21_uart_counter_extract", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class Day21UartCounterExtractTests(unittest.TestCase):
    def setUp(self):
        self.temp_root = REPO_ROOT / "tmp_test" / "uart_counter_extract"
        if self.temp_root.exists():
            shutil.rmtree(self.temp_root)
        self.temp_root.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        if self.temp_root.exists():
            shutil.rmtree(self.temp_root)

    def test_parse_uart_counter_log_selects_latest_complete_snapshot(self):
        module = _load_module()
        log_path = self.temp_root / "uart.log"
        log_path.write_text(
            "\n".join(
                [
                    "shadow-counter meta tag=1 reason=startup rx_batches=0 rx_packets=0",
                    "shadow-counter tag=1 rollback_event_count=0x0000000000000001",
                    "shadow-counter meta tag=2 reason=rx rx_batches=64 rx_packets=128",
                    "shadow-counter tag=2 rollback_event_count=0x0000000000000002",
                    "shadow-counter tag=2 recovery_active_cycles=0x0000000000000008",
                    "shadow-counter tag=2 recovery_last_window_cycles=0x0000000000000004",
                    "shadow-counter tag=2 recovery_max_window_cycles=0x0000000000000006",
                    "shadow-counter tag=2 error_qualified_packet_count=0x0000000000000002",
                    "shadow-counter tag=2 backend_total_cycles=0x0000000000000064",
                    "shadow-counter tag=2 backend_accept_cycles=0x000000000000004B",
                    "shadow-counter tag=2 backend_starvation_cycles=0x0000000000000014",
                    "shadow-counter tag=2 high_water_count=0x0000000000000003",
                    "shadow-counter tag=2 drop_pulse_count=0x0000000000000001",
                    "shadow-counter end tag=2",
                ]
            ),
            encoding="utf-8",
        )

        snapshot = module.parse_uart_counter_log(log_path)

        self.assertEqual(2, snapshot["snapshot_tag"])
        self.assertEqual("rx", snapshot["reason"])
        self.assertEqual(64, snapshot["rx_batches"])
        self.assertEqual(75, snapshot["backend_accept_cycles"])

    def test_write_uart_counter_artifacts_emits_normalized_outputs(self):
        module = _load_module()
        log_path = self.temp_root / "uart.log"
        output_dir = self.temp_root / "out"
        log_path.write_text(
            "\n".join(
                [
                    "shadow-counter meta tag=7 reason=idle rx_batches=128 rx_packets=256",
                    "shadow-counter tag=7 rollback_event_count=0x0000000000000002",
                    "shadow-counter tag=7 recovery_active_cycles=0x0000000000000008",
                    "shadow-counter tag=7 recovery_last_window_cycles=0x0000000000000004",
                    "shadow-counter tag=7 recovery_max_window_cycles=0x0000000000000006",
                    "shadow-counter tag=7 error_qualified_packet_count=0x0000000000000002",
                    "shadow-counter tag=7 backend_total_cycles=0x0000000000000064",
                    "shadow-counter tag=7 backend_accept_cycles=0x000000000000004B",
                    "shadow-counter tag=7 backend_starvation_cycles=0x0000000000000014",
                    "shadow-counter tag=7 high_water_count=0x0000000000000003",
                    "shadow-counter tag=7 drop_pulse_count=0x0000000000000001",
                    "shadow-counter end tag=7",
                ]
            ),
            encoding="utf-8",
        )

        paths = module.write_uart_counter_artifacts(log_path, output_dir, clock_hz=50_000_000)

        for path in paths.values():
            self.assertTrue(path.exists())

        saved_json = json.loads(paths["snapshot_json"].read_text(encoding="utf-8"))
        self.assertEqual(7, saved_json["snapshot_tag"])
        self.assertAlmostEqual(0.75, saved_json["backend_utilization_ratio"])
        self.assertAlmostEqual(0.08, saved_json["recovery_last_window_us"])


if __name__ == "__main__":
    unittest.main()
