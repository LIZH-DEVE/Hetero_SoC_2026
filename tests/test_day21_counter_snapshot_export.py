import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPO_ROOT / "scripts" / "day21_counter_snapshot_export.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("day21_counter_snapshot_export", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class Day21CounterSnapshotExportTests(unittest.TestCase):
    def test_normalize_snapshot_rejects_missing_required_keys(self):
        module = _load_module()

        with self.assertRaises(ValueError):
            module.normalize_counter_snapshot({"rollback_event_count": 1}, clock_hz=50_000_000)

    def test_normalize_snapshot_derives_ratios_and_time_fields(self):
        module = _load_module()

        normalized = module.normalize_counter_snapshot(
            {
                "rollback_event_count": 2,
                "recovery_active_cycles": 8,
                "recovery_last_window_cycles": 4,
                "recovery_max_window_cycles": 6,
                "error_qualified_packet_count": 2,
                "backend_total_cycles": 100,
                "backend_accept_cycles": 75,
                "backend_starvation_cycles": 20,
                "high_water_count": 3,
                "drop_pulse_count": 1,
            },
            clock_hz=50_000_000,
        )

        self.assertEqual(2, normalized["rollback_event_count"])
        self.assertAlmostEqual(0.08, normalized["recovery_last_window_us"])
        self.assertAlmostEqual(0.75, normalized["backend_utilization_ratio"])
        self.assertAlmostEqual(0.20, normalized["backend_starvation_ratio"])

    def test_write_counter_artifacts_emits_json_and_plot_ready_csvs(self):
        module = _load_module()

        snapshot = {
            "rollback_event_count": 2,
            "recovery_active_cycles": 8,
            "recovery_last_window_cycles": 4,
            "recovery_max_window_cycles": 6,
            "error_qualified_packet_count": 2,
            "backend_total_cycles": 100,
            "backend_accept_cycles": 75,
            "backend_starvation_cycles": 20,
            "high_water_count": 3,
            "drop_pulse_count": 1,
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            output_dir = Path(temp_dir)
            paths = module.write_counter_artifacts(snapshot, output_dir, clock_hz=50_000_000)

            for path in paths.values():
                self.assertTrue(path.exists())

            saved_json = json.loads(paths["snapshot_json"].read_text(encoding="utf-8"))
            self.assertEqual(2, saved_json["rollback_event_count"])
            self.assertIn("backend_utilization_ratio", saved_json)

            fig5_csv = paths["fig5_csv"].read_text(encoding="utf-8")
            fig7_csv = paths["fig7_csv"].read_text(encoding="utf-8")
            self.assertIn("recovery_last_window_cycles", fig5_csv)
            self.assertIn("backend_utilization_ratio", fig7_csv)

    def test_load_snapshot_json_accepts_utf8_bom(self):
        module = _load_module()

        snapshot = {
            "rollback_event_count": 1,
            "recovery_active_cycles": 2,
            "recovery_last_window_cycles": 3,
            "recovery_max_window_cycles": 4,
            "error_qualified_packet_count": 5,
            "backend_total_cycles": 6,
            "backend_accept_cycles": 7,
            "backend_starvation_cycles": 8,
            "high_water_count": 9,
            "drop_pulse_count": 10,
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            snapshot_path = Path(temp_dir) / "snapshot.json"
            snapshot_path.write_text(json.dumps(snapshot), encoding="utf-8-sig")

            loaded = module.load_snapshot_json(snapshot_path)
            self.assertEqual(snapshot, loaded)


if __name__ == "__main__":
    unittest.main()
