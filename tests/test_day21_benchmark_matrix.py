import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock
from types import SimpleNamespace


REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPO_ROOT / "scripts" / "day21_benchmark_matrix.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("day21_benchmark_matrix", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class Day21BenchmarkMatrixTests(unittest.TestCase):
    def test_load_control_module_prefers_acl_capable_client(self):
        module = _load_module()

        class NoAclClient:
            pass

        class AclClient:
            def acl_clear(self):
                raise NotImplementedError

            def acl_write(self):
                raise NotImplementedError

        no_acl_module = SimpleNamespace(ControlClient=NoAclClient)
        acl_module = SimpleNamespace(ControlClient=AclClient)

        with mock.patch.object(
            module,
            "_load_module",
            side_effect=[no_acl_module, acl_module],
        ) as loader:
            control_module = module.load_control_module()

        self.assertIs(acl_module, control_module)
        self.assertEqual(2, loader.call_count)

    def test_build_matrix_scenarios_expands_to_18_combinations(self):
        module = _load_module()

        scenarios = module.build_matrix_scenarios()

        self.assertEqual(18, len(scenarios))
        self.assertEqual(
            {"aes_only", "sm4_only", "mixed_alt_50_50"},
            {item["load_mode"] for item in scenarios},
        )
        self.assertEqual({64, 512, 1472}, {item["payload_len"] for item in scenarios})
        self.assertEqual(
            {"acl_off", "acl_on_nonmatching"},
            {item["acl_mode"] for item in scenarios},
        )

    def test_build_scenario_schedule_for_mixed_mode_alternates_algorithms(self):
        module = _load_module()

        payload_map = {
            "aes": b"A" * 64,
            "sm4": b"S" * 64,
        }

        schedule = module.build_scenario_schedule(
            load_mode="mixed_alt_50_50",
            payload_by_algo=payload_map,
            request_count=6,
        )

        self.assertEqual(6, len(schedule))
        self.assertEqual(["aes", "sm4", "aes", "sm4", "aes", "sm4"], [item["algo"] for item in schedule])
        self.assertTrue(all(len(item["payload"]) == 64 for item in schedule))

    def test_build_scenario_schedule_rejects_odd_request_count_for_mixed_mode(self):
        module = _load_module()

        with self.assertRaises(ValueError):
            module.build_scenario_schedule(
                load_mode="mixed_alt_50_50",
                payload_by_algo={"aes": b"A" * 64, "sm4": b"S" * 64},
                request_count=5,
            )

    def test_build_payload_bytes_is_precomputed_and_aligned(self):
        module = _load_module()

        class FakeSendModule:
            AES_DEFAULT_PAYLOAD_HEX = "00112233445566778899aabbccddeeff"
            SM4_DEFAULT_PAYLOAD_HEX = "ffeeddccbbaa99887766554433221100"

        aes_payload = module.build_payload_bytes(FakeSendModule, "aes", 64)
        sm4_payload = module.build_payload_bytes(FakeSendModule, "sm4", 1472)

        self.assertEqual(64, len(aes_payload))
        self.assertEqual(1472, len(sm4_payload))
        self.assertEqual(bytes.fromhex(FakeSendModule.AES_DEFAULT_PAYLOAD_HEX) * 4, aes_payload)
        self.assertEqual(0, len(sm4_payload) % 16)

    def test_reply_matches_expectation_accepts_exact_and_auto_session_reply_modes(self):
        module = _load_module()

        entry = {
            "payload": b"P" * 64,
            "expected": b"E" * 64,
            "dest_port": 4660,
        }

        self.assertTrue(
            module.reply_matches_expectation(entry, "192.168.1.20", ("192.168.1.20", 4660), b"E" * 64)
        )
        self.assertTrue(
            module.reply_matches_expectation(entry, "192.168.1.20", ("192.168.1.20", 4660), b"R" * 64)
        )
        self.assertFalse(
            module.reply_matches_expectation(entry, "192.168.1.20", ("192.168.1.20", 4660), b"P" * 64)
        )
        self.assertFalse(
            module.reply_matches_expectation(entry, "192.168.1.20", ("192.168.1.20", 4661), b"R" * 64)
        )

    def test_build_expected_payloads_uses_shared_dual_enable_user_key_for_both_algorithms(self):
        module = _load_module()

        class FakeSendModule:
            AES_DEFAULT_PAYLOAD_HEX = "00112233445566778899aabbccddeeff"
            SM4_DEFAULT_PAYLOAD_HEX = "ffeeddccbbaa99887766554433221100"
            AES_PORT = 4660
            SM4_PORT = 4661
            calls = []

            @staticmethod
            def derive_binding_aware_expected(algo, payload, binding_id, user_key):
                FakeSendModule.calls.append((algo, payload, binding_id, user_key))
                return algo.encode("ascii") + user_key[:2]

        shared_user_key = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")
        payloads = module.build_expected_payloads(
            FakeSendModule,
            binding_id=0x41583702,
            shared_user_key=shared_user_key,
        )

        self.assertEqual(6, len(FakeSendModule.calls))
        self.assertTrue(all(call[3] == shared_user_key for call in FakeSendModule.calls))
        self.assertEqual(b"aes" + shared_user_key[:2], payloads[64]["aes"]["expected"])
        self.assertEqual(b"sm4" + shared_user_key[:2], payloads[64]["sm4"]["expected"])

    def test_precompute_scenario_assets_builds_schedule_once_per_scenario(self):
        module = _load_module()

        scenarios = module.build_matrix_scenarios()
        precomputed_by_length = {
            64: {
                "aes": {"payload": b"A" * 64, "expected": b"EA", "dest_port": 4660, "local_port": 55160},
                "sm4": {"payload": b"S" * 64, "expected": b"ES", "dest_port": 4661, "local_port": 55161},
            },
            512: {
                "aes": {"payload": b"A" * 512, "expected": b"EA", "dest_port": 4660, "local_port": 55160},
                "sm4": {"payload": b"S" * 512, "expected": b"ES", "dest_port": 4661, "local_port": 55161},
            },
            1472: {
                "aes": {"payload": b"A" * 1472, "expected": b"EA", "dest_port": 4660, "local_port": 55160},
                "sm4": {"payload": b"S" * 1472, "expected": b"ES", "dest_port": 4661, "local_port": 55161},
            },
        }

        with mock.patch.object(module, "build_precomputed_schedule", wraps=module.build_precomputed_schedule) as build_schedule:
            with mock.patch.object(module, "build_precomputed_warmup", wraps=module.build_precomputed_warmup) as build_warmup:
                assets = module.precompute_scenario_assets(
                    scenarios=scenarios,
                    request_count=10,
                    precomputed_by_length=precomputed_by_length,
                )

        self.assertEqual(18, len(assets))
        self.assertEqual(18, build_schedule.call_count)
        self.assertEqual(18, build_warmup.call_count)

    def test_main_uses_shared_dual_enable_key_and_precomputed_assets(self):
        module = _load_module()

        class FakeControlClient:
            def __init__(self):
                self.binding_id = 0x41583702
                self.hello_called = 0
                self.set_key_calls = []
                self.closed = False

            def hello(self):
                self.hello_called += 1

            def set_key(self, algo, user_key=None, dual_enable=False):
                self.set_key_calls.append((algo, user_key, dual_enable))

            def close(self):
                self.closed = True

        fake_client = FakeControlClient()
        shared_user_key = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")

        fake_control_module = SimpleNamespace(
            default_user_key=lambda algo: shared_user_key if algo == "aes" else bytes.fromhex("0123456789abcdeffedcba9876543210"),
            ControlClient=lambda **kwargs: fake_client,
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            with mock.patch.object(module, "load_board_bench_module", return_value=object()):
                with mock.patch.object(module, "load_control_module", return_value=fake_control_module):
                    with mock.patch.object(module, "load_send_tool_module", return_value=object()):
                        with mock.patch.object(module, "capture_baseline_snapshot", return_value={"results": {}}):
                            with mock.patch.object(module, "build_expected_payloads", return_value={64: {}, 512: {}, 1472: {}}) as build_expected:
                                with mock.patch.object(module, "precompute_scenario_assets", return_value=[]) as precompute:
                                    with mock.patch.object(module, "write_bench_matrix_artifacts", return_value=(Path(temp_dir) / "a.json", Path(temp_dir) / "a.md", Path(temp_dir) / "a.csv")):
                                        rc = module.main(
                                            [
                                                "--target-ip",
                                                "192.168.1.20",
                                                "--source-ip",
                                                "192.168.1.11",
                                                "--requests-per-scenario",
                                                "10",
                                                "--output-dir",
                                                temp_dir,
                                            ]
                                        )

        self.assertEqual(0, rc)
        self.assertEqual(1, fake_client.hello_called)
        self.assertEqual([("aes", shared_user_key, True)], fake_client.set_key_calls)
        build_expected.assert_called_once_with(mock.ANY, fake_client.binding_id, shared_user_key)
        precompute.assert_called_once()
        self.assertTrue(fake_client.closed)

    def test_main_rejects_odd_requests_per_scenario(self):
        module = _load_module()

        rc = module.main(
            [
                "--requests-per-scenario",
                "9",
            ]
        )

        self.assertEqual(1, rc)

    def test_compute_acl_deltas_pairs_acl_on_and_off_by_load_and_length(self):
        module = _load_module()

        results = [
            {
                "load_mode": "aes_only",
                "payload_len": 64,
                "acl_mode": "acl_off",
                "avg_latency_us": 10.0,
                "throughput_mb_s": 20.0,
            },
            {
                "load_mode": "aes_only",
                "payload_len": 64,
                "acl_mode": "acl_on_nonmatching",
                "avg_latency_us": 12.5,
                "throughput_mb_s": 18.5,
            },
        ]

        deltas = module.compute_acl_deltas(results)

        self.assertEqual(1, len(deltas))
        self.assertEqual("aes_only", deltas[0]["load_mode"])
        self.assertEqual(64, deltas[0]["payload_len"])
        self.assertAlmostEqual(2.5, deltas[0]["avg_latency_delta_us"])
        self.assertAlmostEqual(-1.5, deltas[0]["throughput_delta_mb_s"])

    def test_render_bench_matrix_markdown_includes_baseline_main_table_and_acl_delta(self):
        module = _load_module()

        report = {
            "baseline_snapshot": {
                "results": {
                    "aes": {"summary": {"avg_speedup": 2.70}},
                    "sm4": {"summary": {"avg_speedup": 2.10}},
                }
            },
            "matrix_results": [
                {
                    "load_mode": "mixed_alt_50_50",
                    "payload_len": 64,
                    "acl_mode": "acl_on_nonmatching",
                    "request_count": 10,
                    "success_count": 10,
                    "timeout_count": 0,
                    "mismatch_count": 0,
                    "success_rate": 1.0,
                    "avg_latency_us": 15.0,
                    "p50_latency_us": 14.0,
                    "p95_latency_us": 18.0,
                    "throughput_mb_s": 8.0,
                    "aes_request_count": 5,
                    "sm4_request_count": 5,
                    "aes_avg_latency_us": 14.5,
                    "sm4_avg_latency_us": 15.5,
                }
            ],
            "acl_deltas": [
                {
                    "load_mode": "mixed_alt_50_50",
                    "payload_len": 64,
                    "avg_latency_delta_us": 1.5,
                    "throughput_delta_mb_s": -0.5,
                }
            ],
        }

        markdown = module.render_bench_matrix_markdown(report)

        self.assertIn("# Phase C Board Benchmark Matrix Summary", markdown)
        self.assertIn("## Baseline Snapshot", markdown)
        self.assertIn("## Host Matrix", markdown)
        self.assertIn("## ACL Delta", markdown)
        self.assertIn("ACL on (non-matching rule)", markdown)
        self.assertIn("mixed_alt_50_50", markdown)
        self.assertNotIn("64B same-board speedup", markdown)

    def test_write_bench_matrix_artifacts_emits_json_markdown_and_csv(self):
        module = _load_module()

        report = {
            "baseline_snapshot": {"results": {}},
            "matrix_results": [
                {
                    "load_mode": "aes_only",
                    "payload_len": 64,
                    "acl_mode": "acl_off",
                    "request_count": 2,
                    "success_count": 2,
                    "timeout_count": 0,
                    "mismatch_count": 0,
                    "success_rate": 1.0,
                    "avg_latency_us": 10.0,
                    "p50_latency_us": 10.0,
                    "p95_latency_us": 10.0,
                    "throughput_mb_s": 5.0,
                }
            ],
            "acl_deltas": [],
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            json_path, markdown_path, csv_path = module.write_bench_matrix_artifacts(
                report, Path(temp_dir)
            )

            self.assertTrue(json_path.exists())
            self.assertTrue(markdown_path.exists())
            self.assertTrue(csv_path.exists())
            self.assertEqual("bench_matrix_report.json", json_path.name)
            self.assertEqual("bench_matrix_summary.md", markdown_path.name)
            self.assertEqual("bench_matrix_results.csv", csv_path.name)

            saved_report = json.loads(json_path.read_text(encoding="utf-8"))
            self.assertIn("matrix_results", saved_report)
            self.assertIn("load_mode,payload_len,acl_mode", csv_path.read_text(encoding="utf-8"))

    def test_hot_path_contract_uses_try_finally_gc_guards_and_no_subprocess(self):
        module = _load_module()
        source = Path(module.__file__).read_text(encoding="utf-8")

        self.assertIn("gc.disable()", source)
        self.assertIn("gc.enable()", source)
        self.assertIn("gc.collect()", source)
        self.assertIn("try:", source)
        self.assertIn("finally:", source)
        self.assertNotIn("subprocess.run(", source)
        self.assertNotIn("subprocess.Popen(", source)
        self.assertIn("precompute_scenario_assets(", source)
        self.assertIn("scenario_assets = precompute_scenario_assets(", source)


if __name__ == "__main__":
    unittest.main()
