import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace


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

    def test_calculate_board_bench_metrics_computes_latency_and_speedup(self):
        module = _load_module()

        metrics = module.calculate_board_bench_metrics(
            {
                "algo": "aes",
                "repeats": 8,
                "records": [
                    {"length": 128, "sw_us": 160, "hw_us": 40},
                    {"length": 512, "sw_us": 320, "hw_us": 80},
                ],
            }
        )

        self.assertEqual("aes", metrics["algo"])
        self.assertEqual(8, metrics["repeats"])
        self.assertEqual(2, len(metrics["records"]))
        self.assertAlmostEqual(20.0, metrics["records"][0]["sw_avg_latency_us"])
        self.assertAlmostEqual(5.0, metrics["records"][0]["hw_avg_latency_us"])
        self.assertAlmostEqual(4.0, metrics["records"][0]["speedup"])
        self.assertGreater(
            metrics["records"][0]["hw_throughput_mb_s"],
            metrics["records"][0]["sw_throughput_mb_s"],
        )

    def test_calculate_board_bench_metrics_rejects_invalid_record_values(self):
        module = _load_module()

        with self.assertRaises(ValueError):
            module.calculate_board_bench_metrics(
                {
                    "algo": "sm4",
                    "repeats": 0,
                    "records": [{"length": 128, "sw_us": 100, "hw_us": 50}],
                }
            )

        with self.assertRaises(ValueError):
            module.calculate_board_bench_metrics(
                {
                    "algo": "sm4",
                    "repeats": 4,
                    "records": [{"length": 128, "sw_us": 0, "hw_us": 50}],
                }
            )

    def test_render_board_bench_markdown_contains_required_columns(self):
        module = _load_module()

        report = {
            "mode": "board_bench",
            "target": {"ip": "192.168.1.20", "source_ip": "192.168.1.11"},
            "results": {
                "aes": {
                    "algo": "aes",
                    "repeats": 8,
                    "records": [
                        {
                            "length_bytes": 128,
                            "sw_total_us": 160,
                            "hw_total_us": 40,
                            "sw_avg_latency_us": 20.0,
                            "hw_avg_latency_us": 5.0,
                            "sw_throughput_mb_s": 6.10,
                            "hw_throughput_mb_s": 24.41,
                            "speedup": 4.0,
                        }
                    ],
                },
                "sm4": {
                    "algo": "sm4",
                    "repeats": 8,
                    "records": [
                        {
                            "length_bytes": 128,
                            "sw_total_us": 200,
                            "hw_total_us": 50,
                            "sw_avg_latency_us": 25.0,
                            "hw_avg_latency_us": 6.25,
                            "sw_throughput_mb_s": 4.88,
                            "hw_throughput_mb_s": 19.53,
                            "speedup": 4.0,
                        }
                    ],
                },
            },
        }

        markdown = module.render_board_bench_markdown(report)

        self.assertIn("# Phase C Board Benchmark Summary", markdown)
        self.assertIn("## AES", markdown)
        self.assertIn("## SM4", markdown)
        self.assertIn("| Length (B) | Repeats | SW Total (us) | HW Total (us) |", markdown)
        self.assertIn("PS software baseline", markdown)
        self.assertIn("same-board hardware path", markdown)

    def test_write_board_bench_artifacts_emits_json_and_markdown(self):
        module = _load_module()

        report = {
            "mode": "board_bench",
            "results": {
                "aes": {
                    "algo": "aes",
                    "repeats": 8,
                    "records": [
                        {
                            "length_bytes": 128,
                            "sw_total_us": 160,
                            "hw_total_us": 40,
                            "sw_avg_latency_us": 20.0,
                            "hw_avg_latency_us": 5.0,
                            "sw_throughput_mb_s": 6.10,
                            "hw_throughput_mb_s": 24.41,
                            "speedup": 4.0,
                        }
                    ],
                }
            },
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            json_path, markdown_path = module.write_board_bench_artifacts(
                report, Path(temp_dir)
            )

            self.assertTrue(json_path.exists())
            self.assertTrue(markdown_path.exists())
            self.assertEqual("board_bench_report.json", json_path.name)
            self.assertEqual("board_bench_summary.md", markdown_path.name)

            saved_report = json.loads(json_path.read_text(encoding="utf-8"))
            self.assertEqual("board_bench", saved_report["mode"])
            self.assertIn("Phase C Board Benchmark Summary", markdown_path.read_text(encoding="utf-8"))

    def test_build_board_bench_report_uses_avg_target_not_short_packet_rows(self):
        module = _load_module()

        report = module.build_board_bench_report(
            bench_ip="192.168.1.20",
            source_ip="192.168.1.11",
            control_port=4662,
            repeats=8,
            target_speedup=1.0,
            session_info={"session_id": 1, "binding_id": 0x41583702},
            metrics_by_algo={
                "aes": {
                    "algo": "aes",
                    "repeats": 8,
                    "records": [
                        {"length_bytes": 16, "speedup": 0.60},
                        {"length_bytes": 32, "speedup": 0.70},
                        {"length_bytes": 512, "speedup": 1.40},
                        {"length_bytes": 1472, "speedup": 1.80},
                    ],
                    "summary": {
                        "record_count": 4,
                        "min_speedup": 0.60,
                        "max_speedup": 1.80,
                        "avg_speedup": 1.125,
                    },
                },
                "sm4": {
                    "algo": "sm4",
                    "repeats": 8,
                    "records": [
                        {"length_bytes": 16, "speedup": 0.55},
                        {"length_bytes": 32, "speedup": 0.65},
                        {"length_bytes": 512, "speedup": 1.35},
                        {"length_bytes": 1472, "speedup": 1.75},
                    ],
                    "summary": {
                        "record_count": 4,
                        "min_speedup": 0.55,
                        "max_speedup": 1.75,
                        "avg_speedup": 1.075,
                    },
                },
            },
        )

        self.assertEqual(1.0, report["target"]["speedup"])
        self.assertTrue(report["results"]["aes"]["meets_target"])
        self.assertTrue(report["results"]["sm4"]["meets_target"])
        self.assertTrue(report["overall"]["meets_target"])

    def test_render_board_bench_markdown_includes_target_and_short_packet_note(self):
        module = _load_module()

        report = {
            "mode": "board_bench",
            "target": {
                "ip": "192.168.1.20",
                "source_ip": "192.168.1.11",
                "control_port": 4662,
                "repeats": 8,
                "speedup": 1.0,
            },
            "overall": {"meets_target": False},
            "results": {
                "aes": {
                    "algo": "aes",
                    "repeats": 8,
                    "meets_target": False,
                    "records": [
                        {
                            "length_bytes": 16,
                            "sw_total_us": 160,
                            "hw_total_us": 200,
                            "sw_avg_latency_us": 20.0,
                            "hw_avg_latency_us": 25.0,
                            "sw_throughput_mb_s": 6.10,
                            "hw_throughput_mb_s": 4.88,
                            "speedup": 0.8,
                        }
                    ],
                    "summary": {
                        "record_count": 1,
                        "min_speedup": 0.8,
                        "max_speedup": 0.8,
                        "avg_speedup": 0.8,
                    },
                }
            },
        }

        markdown = module.render_board_bench_markdown(report)

        self.assertIn("Target speedup gate: average speedup per algorithm must be `>= 1.000000x`.", markdown)
        self.assertIn("Short payload note: `16B` and `32B` rows may remain `<1.0x`", markdown)
        self.assertIn("Target result: `FAIL`", markdown)

    def test_stage2_defaults_raise_bench_repeats_to_1000(self):
        module = _load_module()

        self.assertEqual(1000, module.DEFAULT_BENCH_REPEATS)

        args = module.parse_args(
            [
                "--bench-ip",
                "192.168.1.20",
                "--source-ip",
                "192.168.1.11",
            ]
        )

        self.assertEqual(1000, args.repeats)

    def test_parse_args_accepts_proof_uart_log(self):
        module = _load_module()

        args = module.parse_args(["--proof-uart-log", "proof.log"])

        self.assertEqual(Path("proof.log"), args.proof_uart_log)
        self.assertEqual(1000, args.expected_proof_repeats)

    def test_parse_stage2_proof_uart_log_extracts_rows_and_diagnostics(self):
        module = _load_module()

        proof_log = "\n".join(
            [
                "AX7020 DMA gateway hybrid perf proof image",
                "PROOF_CONFIG repeats=1000 ring_entries=2048 usable_desc=2047",
                "PROOF_ROW algo=aes length=16 repeats=1000 sw_us=1000 hw_us=800 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=55 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=aes length=32 repeats=1000 sw_us=1500 hw_us=900 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=60 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=aes length=128 repeats=1000 sw_us=5000 hw_us=3500 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=70 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=aes length=512 repeats=1000 sw_us=18000 hw_us=11000 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=80 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=aes length=1472 repeats=1000 sw_us=52000 hw_us=30000 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=90 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_AES PASS records=5",
                "PROOF_ROW algo=sm4 length=16 repeats=1000 sw_us=1200 hw_us=950 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=40 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=sm4 length=32 repeats=1000 sw_us=1600 hw_us=1100 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=45 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=sm4 length=128 repeats=1000 sw_us=6000 hw_us=3900 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=50 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=sm4 length=512 repeats=1000 sw_us=21000 hw_us=13000 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=65 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=sm4 length=1472 repeats=1000 sw_us=60000 hw_us=34000 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=75 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_SM4 PASS records=5",
                "DMA gateway hybrid perf proof PASS",
            ]
        )

        parsed = module.parse_stage2_proof_uart_log(proof_log, expected_repeats=1000)

        self.assertEqual("uart_stage2_proof", parsed["source"])
        self.assertTrue(parsed["overall_pass"])
        self.assertEqual(1000, parsed["repeats"])
        self.assertEqual(5, len(parsed["results"]["aes"]["records"]))
        self.assertEqual(5, len(parsed["results"]["sm4"]["records"]))
        self.assertEqual(1, parsed["results"]["aes"]["diagnostics"]["doorbell_count"])
        self.assertTrue(parsed["results"]["aes"]["diagnostics"]["single_launch_used"])
        self.assertEqual(0, parsed["results"]["sm4"]["diagnostics"]["cipher_mismatch_count"])

    def test_render_board_bench_markdown_includes_stage2_batch_diagnostics(self):
        module = _load_module()

        report = {
            "mode": "board_bench",
            "target": {
                "ip": "192.168.1.20",
                "source_ip": "192.168.1.11",
                "control_port": 4662,
                "repeats": 1000,
                "speedup": 1.0,
            },
            "overall": {"meets_target": True},
            "results": {
                "aes": {
                    "algo": "aes",
                    "repeats": 1000,
                    "meets_target": True,
                    "diagnostics": {
                        "batch_descriptor_count": 1000,
                        "single_launch_used": True,
                        "doorbell_count": 1,
                        "last_descriptor_poll_count": 123,
                        "actual_len_mismatch_count": 0,
                    },
                    "records": [
                        {
                            "length_bytes": 16,
                            "sw_total_us": 1000,
                            "hw_total_us": 800,
                            "sw_avg_latency_us": 1.0,
                            "hw_avg_latency_us": 0.8,
                            "sw_throughput_mb_s": 15.0,
                            "hw_throughput_mb_s": 18.0,
                            "speedup": 1.25,
                        }
                    ],
                    "summary": {
                        "record_count": 1,
                        "min_speedup": 1.25,
                        "max_speedup": 1.25,
                        "avg_speedup": 1.25,
                    },
                }
            },
        }

        markdown = module.render_board_bench_markdown(report)

        self.assertIn("single-launch SG batch", markdown)
        self.assertIn("Descriptor count", markdown)
        self.assertIn("Doorbell count", markdown)
        self.assertIn("Last descriptor poll count", markdown)

    def test_run_proof_uart_mode_fails_when_any_algo_misses_target(self):
        module = _load_module()

        proof_log = "\n".join(
            [
                "AX7020 DMA gateway hybrid perf proof image",
                "PROOF_CONFIG repeats=1000 ring_entries=2048 usable_desc=2047",
                "PROOF_ROW algo=aes length=16 repeats=1000 sw_us=1000 hw_us=980 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=10 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=aes length=32 repeats=1000 sw_us=2000 hw_us=1800 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=10 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=aes length=128 repeats=1000 sw_us=8000 hw_us=7000 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=10 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=aes length=512 repeats=1000 sw_us=32000 hw_us=26000 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=10 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=aes length=1472 repeats=1000 sw_us=92000 hw_us=70000 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=10 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_AES PASS records=5",
                "PROOF_ROW algo=sm4 length=16 repeats=1000 sw_us=1000 hw_us=3000 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=10 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=sm4 length=32 repeats=1000 sw_us=2000 hw_us=5000 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=10 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=sm4 length=128 repeats=1000 sw_us=8000 hw_us=15000 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=10 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=sm4 length=512 repeats=1000 sw_us=32000 hw_us=52000 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=10 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_ROW algo=sm4 length=1472 repeats=1000 sw_us=92000 hw_us=150000 batch_descriptor_count=1000 single_launch_used=1 doorbell_count=1 last_descriptor_poll_count=10 actual_len_mismatch_count=0 cipher_mismatch_count=0 descriptor_error_count=0 completion_timeout_count=0",
                "PROOF_SM4 PASS records=5",
                "DMA gateway hybrid perf proof PASS",
            ]
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "proof.log"
            log_path.write_text(proof_log, encoding="utf-8")
            args = SimpleNamespace(
                counters_json=None,
                ila_log=None,
                demo_mode=False,
                bench_ip=None,
                proof_uart_log=log_path,
                expected_proof_repeats=1000,
                target_speedup=1.0,
                output_dir=Path(temp_dir),
            )

            self.assertEqual(2, module.run_proof_uart_mode(args))

    def test_run_board_benchmark_mode_fails_when_any_algo_misses_target(self):
        module = _load_module()

        original_runner = module.run_board_bench_session
        try:
            module.run_board_bench_session = lambda **_kwargs: {
                "session_id": 1,
                "binding_id": 0x41583702,
                "results": {
                    "aes": {
                        "algo": "aes",
                        "repeats": 8,
                        "records": [
                            {"length": 16, "sw_us": 10, "hw_us": 20},
                            {"length": 1472, "sw_us": 100, "hw_us": 200},
                        ],
                    },
                    "sm4": {
                        "algo": "sm4",
                        "repeats": 8,
                        "records": [
                            {"length": 16, "sw_us": 10, "hw_us": 20},
                            {"length": 1472, "sw_us": 100, "hw_us": 200},
                        ],
                    },
                },
            }

            with tempfile.TemporaryDirectory() as temp_dir:
                args = SimpleNamespace(
                    counters_json=None,
                    ila_log=None,
                    demo_mode=False,
                    bench_ip="192.168.1.20",
                    source_ip="192.168.1.11",
                    control_port=4662,
                    control_timeout=3.0,
                    algos="aes,sm4",
                    repeats=8,
                    target_speedup=1.0,
                    output_dir=Path(temp_dir),
                )

                self.assertEqual(2, module.run_board_benchmark_mode(args))
        finally:
            module.run_board_bench_session = original_runner

    def test_run_board_benchmark_mode_rejects_mixed_demo_and_counter_inputs(self):
        module = _load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            args = SimpleNamespace(
                counters_json=Path(temp_dir) / "sample.json",
                ila_log=None,
                demo_mode=True,
                bench_ip="192.168.1.20",
                source_ip="192.168.1.11",
                control_port=4662,
                control_timeout=3.0,
                algos="aes,sm4",
                repeats=8,
                output_dir=Path(temp_dir),
            )

            self.assertEqual(1, module.run_board_benchmark_mode(args))


if __name__ == "__main__":
    unittest.main()
