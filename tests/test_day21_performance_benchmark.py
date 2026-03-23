import importlib.util
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPO_ROOT / "scripts" / "day21_performance_benchmark.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("day21_performance_benchmark", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class Day21PerformanceBenchmarkTests(unittest.TestCase):
    def test_parse_ila_monitor_output_extracts_real_counters(self):
        module = _load_module()

        sample = module.parse_ila_monitor_output(
            "\n".join(
                [
                    "Monitoring performance for 10000ms...",
                    "FastPath Packets: 1234",
                    "Bypass Packets: 56",
                    "256-Beat Bursts: 78",
                    "128-Beat Bursts: 9",
                ]
            )
        )

        self.assertEqual(1234, sample["fastpath_cnt"])
        self.assertEqual(56, sample["bypass_cnt"])
        self.assertEqual(78, sample["burst_256_cnt"])
        self.assertEqual(9, sample["burst_128_cnt"])
        self.assertEqual(10_000_000, sample["sample_duration_us"])

    def test_load_hardware_sample_rejects_missing_real_input(self):
        module = _load_module()

        with self.assertRaises(ValueError):
            module.load_hardware_sample(None, None, demo_mode=False)

    def test_load_hardware_sample_accepts_explicit_demo_mode(self):
        module = _load_module()

        sample, source, acceptance_eligible = module.load_hardware_sample(
            None, None, demo_mode=True
        )

        self.assertEqual("demo", source)
        self.assertFalse(acceptance_eligible)
        self.assertIn("fastpath_cnt", sample)

    def test_load_hardware_sample_reads_ila_log_file(self):
        module = _load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "ila.log"
            log_path.write_text(
                "\n".join(
                    [
                        "Monitoring performance for 250ms...",
                        "FastPath Packets: 200",
                        "Bypass Packets: 5",
                        "256-Beat Bursts: 11",
                        "128-Beat Bursts: 7",
                    ]
                ),
                encoding="utf-8",
            )

            sample, source, acceptance_eligible = module.load_hardware_sample(
                None, log_path, demo_mode=False
            )

        self.assertEqual("ila_log", source)
        self.assertTrue(acceptance_eligible)
        self.assertEqual(250_000, sample["sample_duration_us"])


if __name__ == "__main__":
    unittest.main()
